/// JSON.Decode.Implementation.swift
/// swift-json
///
/// Wholesale JSON parser for the contiguous-bytes case.
///
/// Relocated to `JSON.Decode.Implementation` namespace under Arc 1.6
/// — the wholesale parser is implementation and lives under the
/// `JSON.*` namespace, not the L2 `RFC_8259.*` spec namespace. Phase
/// A1 of the Tier-4 parse-performance work
/// (`swift-foundations/swift-json/Research/parse-performance-architecture.md`),
/// rebased onto `Lexer.Scanner` from swift-lexer-primitives per the
/// streaming-deserialize placement audit's Ticket T-1
/// (`swift-institute/Audits/streaming-deserialize-placement-audit.md`).
///
/// Internal type — exposed only to the `JSON.Decode` dispatcher and
/// `JSON.Coder.parse`. Emits `RFC_8259.Value` (the L2 spec value
/// type) so consumers can use the result with the Codable conformance
/// directly.

public import ASCII_Decimal_Parser_Primitives
public import Lexer_Primitives
public import RFC_8259
@_spi(Unsafe) public import Array_Primitives
// The small-column tower is `public import` because the lexer helpers are `@inlinable` and need the
// column's conformances visible to inlined clients ([MemberImportVisibility]) — matching the existing
// `Array_Primitives` public import. The JSON public API surface is unchanged.
public import Buffer_Primitive
public import Buffer_Linear_Primitive
public import Buffer_Linear_Primitives
public import Storage_Primitive
public import Storage_Contiguous_Primitives
public import Memory_Allocator_Primitive
public import Memory_Small_Primitives
public import Byte_Primitive
public import Index_Primitives

// The number-lexer scratch accumulator `SmallByteArray` (the inline⊕heap small column,
// `Memory.Small<24>`) is declared once in `JSON.Pull.Stream+Payload.swift` and shared module-wide
// (`@usableFromInline`). The tower imports above are still required in THIS file because
// `lexNumberValue()` is `@inlinable` and the column's conformances must be visible here too.

extension JSON.Decode {
    /// Wholesale JSON parser.
    ///
    /// `~Copyable & ~Escapable` per the cursor it owns
    /// (`Lexer_Primitives.Lexer.Scanner`). Drives the lexer + value-tree
    /// construction in one pass; reuses the public `RFC_8259.Value`,
    /// `RFC_8259.Object`, `RFC_8259.Array`, `RFC_8259.Number`, and
    /// `RFC_8259.Token` types verbatim.
    ///
    /// Not a public type. The static `parse(_:maxDepth:)` entry point
    /// is the only call site from `JSON.Decode.parse` and
    /// `JSON.Coder.parse`.
    @safe
    @usableFromInline
    internal struct Implementation: ~Copyable, ~Escapable {
        @usableFromInline
        internal var scanner: Lexer_Primitives.Lexer.Scanner

        /// Current nesting depth.
        @usableFromInline
        internal var depth: Int

        /// Maximum allowed nesting depth.
        @usableFromInline
        internal let maxDepth: Int

        /// Reusable scratch buffer for `lexString`'s byte accumulation.
        ///
        /// One owned per parse; `removeAll(keepingCapacity: true)`
        /// between strings amortises the per-string allocation across
        /// the whole parse.
        @usableFromInline
        internal var stringScratch: [UInt8]

        @inlinable
        @_lifetime(borrow bytes)
        internal init(_ bytes: borrowing Swift.Span<Byte>, maxDepth: Int) {
            self.scanner = Lexer_Primitives.Lexer.Scanner(bytes)
            self.depth = 0
            self.maxDepth = maxDepth
            var scratch: [UInt8] = []
            scratch.reserveCapacity(64)
            self.stringScratch = scratch
        }
    }
}

// MARK: - Entry point

extension JSON.Decode.Implementation {
    /// Parses the span and returns a JSON value.
    @inlinable
    internal static func parse(
        _ bytes: borrowing Swift.Span<Byte>,
        maxDepth: Int
    ) throws(RFC_8259.Error) -> RFC_8259.Value {
        var parser = JSON.Decode.Implementation(bytes, maxDepth: maxDepth)
        let value = try parser.parse()
        return value
    }

    /// Parses the input and returns a JSON value.
    @inlinable
    @_lifetime(self: copy self)
    internal mutating func parse() throws(RFC_8259.Error) -> RFC_8259.Value {
        let value = try parseValue()

        // Ensure no trailing content (except whitespace).
        skipWhitespace()
        if !scanner.isAtEnd {
            throw .trailingContent(at: currentPosition())
        }

        return value
    }
}

// MARK: - Current-position helper

extension JSON.Decode.Implementation {
    /// Builds `RFC_8259.Position` from the scanner's current cursor.
    /// Line:column is computed by source scan via
    /// ``Lexer/Scanner/location(at:)`` — O(N) at the throw site,
    /// zero cost on the hot path. JSON tokens cannot contain raw
    /// newlines (RFC 8259 §7) so the parser skips per-byte tracker
    /// updates in `skipWhitespace`.
    @inlinable
    internal func currentPosition() -> RFC_8259.Position {
        let pos = scanner.position
        return RFC_8259.Position(offset: pos, location: scanner.location(at:pos))
    }

    /// Builds `RFC_8259.Position` from a previously captured cursor.
    /// Resolves line:column via the source scan only when an error
    /// fires — the hot path captures cheap `Text.Position` and pays
    /// no tracker arithmetic per token.
    @inlinable
    internal func position(at cursor: Text.Position) -> RFC_8259.Position {
        RFC_8259.Position(offset: cursor, location: scanner.location(at:cursor))
    }
}

// MARK: - Value parsing

extension JSON.Decode.Implementation {
    /// Parses a JSON value.
    ///
    /// Reads the next non-whitespace byte and dispatches by ASCII byte
    /// — no token-level lookahead, no `Optional<Token>` storage.
    @inlinable
    @_lifetime(self: copy self)
    internal mutating func parseValue() throws(RFC_8259.Error) -> RFC_8259.Value {
        skipWhitespace()

        // Type-up: lift to ASCII.Code at the peek boundary so cases match
        // ASCII.Code constants directly (JSON tokens are strict ASCII).
        guard let code: ASCII.Code = scanner.peek() else {
            throw .unexpectedEndOfInput(at: currentPosition(), expected: .value)
        }

        switch code {
        case .leftBrace:              // {
            scanner.advance()
            return try parseObject()

        case .leftBracket:            // [
            scanner.advance()
            return try parseArray()

        case .quotationMark:          // "
            let s = try lexStringValue()
            return .string(s)

        case .n:                      // n (null)
            try expectLiteral([.n, .u, .l, .l])
            return .null

        case .t:                      // t (true)
            try expectLiteral([.t, .r, .u, .e])
            return .bool(true)

        case .f:                      // f (false)
            try expectLiteral([.f, .a, .l, .s, .e])
            return .bool(false)

        case .hyphen,                 // -
             .`0`...ASCII.Code.`9`:   // 0-9
            let n = try lexNumberValue()
            return .number(n)

        default:
            throw .unexpectedToken(
                at: currentPosition(),
                found: .unknown(code.byte),
                expected: .value
            )
        }
    }
}

// MARK: - Array parsing (called after `[` is consumed)

extension JSON.Decode.Implementation {
    @inlinable
    @_lifetime(self: copy self)
    internal mutating func parseArray() throws(RFC_8259.Error) -> RFC_8259.Value {
        depth += 1
        if depth > maxDepth {
            throw .depthExceeded(at: currentPosition(), limit: maxDepth)
        }
        defer { depth -= 1 }

        var elements: [RFC_8259.Value] = []
        // Pre-reserve a small capacity to eliminate the first 1–2
        // Array doublings on leaf arrays. `canada.json` has 55 K
        // leaf `[lng, lat]` arrays where this matches exactly; on
        // larger arrays the extra capacity is harmless. See
        // parse-performance-canada-anomaly.md.
        elements.reserveCapacity(4)

        skipWhitespace()
        // Empty array: `[ ]`.
        if let code: ASCII.Code = scanner.peek(), code == .rightBracket {
            scanner.advance()
            return .array(RFC_8259.Array(elements))
        }

        // First value.
        elements.append(try parseValue())

        // Subsequent values.
        while true {
            skipWhitespace()
            // Type-up: lift to ASCII.Code at the peek boundary.
            guard let code: ASCII.Code = scanner.peek() else {
                throw .unexpectedEndOfInput(at: currentPosition(), expected: .arrayEnd)
            }
            switch code {
            case .rightBracket:
                scanner.advance()
                return .array(RFC_8259.Array(elements))
            case .comma:
                scanner.advance()
                elements.append(try parseValue())
            default:
                throw .unexpectedToken(
                    at: currentPosition(),
                    found: .unknown(code.byte),
                    expected: .commaOrEnd
                )
            }
        }
    }
}

// MARK: - Object parsing (called after `{` is consumed)

extension JSON.Decode.Implementation {
    @inlinable
    @_lifetime(self: copy self)
    internal mutating func parseObject() throws(RFC_8259.Error) -> RFC_8259.Value {
        depth += 1
        if depth > maxDepth {
            throw .depthExceeded(at: currentPosition(), limit: maxDepth)
        }
        defer { depth -= 1 }

        var members: [(key: String, value: RFC_8259.Value)] = []

        skipWhitespace()
        // Empty object: `{ }`.
        if let code: ASCII.Code = scanner.peek(), code == .rightBrace {
            scanner.advance()
            return .object(RFC_8259.Object(members))
        }

        // First member.
        members.append(try parseMember())

        // Subsequent members.
        while true {
            skipWhitespace()
            // Type-up: lift to ASCII.Code at the peek boundary.
            guard let code: ASCII.Code = scanner.peek() else {
                throw .unexpectedEndOfInput(at: currentPosition(), expected: .objectEnd)
            }
            switch code {
            case .rightBrace:
                scanner.advance()
                return .object(RFC_8259.Object(members))
            case .comma:
                scanner.advance()
                members.append(try parseMember())
            default:
                throw .unexpectedToken(
                    at: currentPosition(),
                    found: .unknown(code.byte),
                    expected: .commaOrEnd
                )
            }
        }
    }

    /// Parses a single object member (key: value).
    @inlinable
    @_lifetime(self: copy self)
    internal mutating func parseMember() throws(RFC_8259.Error) -> (key: String, value: RFC_8259.Value) {
        skipWhitespace()
        // Type-up: lift to ASCII.Code at the peek boundary.
        guard let firstCode: ASCII.Code = scanner.peek() else {
            throw .unexpectedEndOfInput(at: currentPosition(), expected: .objectKey)
        }
        guard firstCode == .quotationMark else {
            throw .unexpectedToken(
                at: currentPosition(),
                found: .unknown(firstCode.byte),
                expected: .objectKey
            )
        }
        let key = try lexStringValue()

        // Expect colon.
        skipWhitespace()
        guard let colonCode: ASCII.Code = scanner.peek() else {
            throw .unexpectedEndOfInput(at: currentPosition(), expected: .colon)
        }
        guard colonCode == .colon else {
            throw .unexpectedToken(
                at: currentPosition(),
                found: .unknown(colonCode.byte),
                expected: .colon
            )
        }
        scanner.advance()

        // Parse value.
        let value = try parseValue()
        return (key: key, value: value)
    }
}

// MARK: - Whitespace

extension JSON.Decode.Implementation {
    /// Skips whitespace bytes.
    ///
    /// Uses an inlined four-way comparison against the four JSON
    /// whitespace bytes (space, tab, CR, LF) instead of the
    /// `RFC_8259.isWhitespace` Set lookup. The post-A1 profile
    /// (10 × 86 MB) showed `Hasher._hash(seed:bytes:count:)` as a
    /// significant cost under `skipWhitespace` — the Set-backed
    /// predicate hashes every byte. Direct equality checks are
    /// branchless on ARM64 after constant folding.
    ///
    /// JSON tokens (strings, numbers, literals) cannot contain raw
    /// 0x0A / 0x0D — they MUST be escaped per RFC 8259 §7 — so the
    /// only place newlines can appear is here, in inter-token
    /// whitespace. The parser elides per-newline tracker updates on
    /// the hot path; error-site line:column is recovered via the
    /// O(N) ``Lexer/Scanner/location(at:)`` scan at throw sites.
    @inlinable
    @_lifetime(self: copy self)
    internal mutating func skipWhitespace() {
        while let byte = scanner.peek() {
            // Inline the whitespace check: space (0x20), tab (0x09),
            // LF (0x0A), CR (0x0D). RFC 8259 §2.
            // Single-arm switch: with no tracker maintained, CR and LF
            // need no special handling — CRLF is consumed as two
            // individual whitespace bytes, identical to space-tab.
            switch byte {
            case 0x20, 0x09, 0x0A, 0x0D:
                scanner.advance()
            default:
                return
            }
        }
    }
}

// MARK: - Literals

extension JSON.Decode.Implementation {
    /// Expects the given literal bytes (called after the first byte
    /// has been peeked but NOT advanced).
    ///
    /// Position computation is deferred to error sites only — the
    /// hot path doesn't materialise `RFC_8259.Position` per literal.
    /// The literal start (cursor + location) is captured before the
    /// first byte; on mismatch we report the captured position so the
    /// diagnostic points at the start of the failed literal rather
    /// than the failing byte.
    @inlinable
    @_lifetime(self: copy self)
    internal mutating func expectLiteral(_ expected: [ASCII.Code]) throws(RFC_8259.Error) {
        let startCursor = scanner.position
        for expectedCode in expected {
            // Type-up: lift to ASCII.Code at the peek boundary.
            guard let code: ASCII.Code = scanner.peek() else {
                throw .unexpectedEndOfInput(
                    at: currentPosition(),
                    expected: .value
                )
            }
            guard code == expectedCode else {
                throw .unexpectedToken(
                    at: position(at: startCursor),
                    found: .unknown(code.byte),
                    expected: .value
                )
            }
            scanner.advance()
        }
    }
}

// MARK: - Strings (returns String directly — no Token wrapping)

extension JSON.Decode.Implementation {
    /// Lexes a JSON string (after the leading `"` has been peeked but
    /// NOT advanced). Returns the decoded `String` directly. The Token
    /// wrapping that the generic lexer produces is bypassed — the
    /// Implementation doesn't need it.
    ///
    /// Position computation is deferred to error sites only — the
    /// hot path doesn't materialise `RFC_8259.Position` per string.
    @inlinable
    @_lifetime(self: copy self)
    internal mutating func lexStringValue() throws(RFC_8259.Error) -> String {
        let startCursor = scanner.position

        scanner.advance() // Consume opening `"`.

        stringScratch.removeAll(keepingCapacity: true)
        var isASCII = true

        // Drive the loop on the RAW byte. JSON strings are UTF-8, so the
        // content may contain bytes >= 0x80 (multi-byte sequences) that
        // ASCII.Code cannot carry. The previous `while let code: ASCII.Code`
        // bound the typed `peek` overload, which returns nil for any byte
        // >= 0x80 — terminating the loop on the first non-ASCII byte and
        // mis-reporting every such string as unterminated (RFC 8259 §7
        // permits any Unicode scalar except `"`, `\`, and 0x00...0x1F).
        // Lift to ASCII.Code only to match the structural cases (quote /
        // backslash / control, all < 0x80) per the byte-discipline rubric
        // ([API-BYTE-004]); a byte outside the 7-bit range is string content
        // appended raw.
        while let byte: Byte = scanner.peek() {
            guard byte.underlying < 0x80 else {
                // Multi-byte UTF-8 lead/continuation byte — string content.
                isASCII = false
                stringScratch.append(byte.underlying)
                scanner.advance()
                continue
            }
            // In range: lift unchecked (the guard above IS the throwing
            // init's validation) so the structural cases match ASCII.Code
            // constants directly.
            let code = ASCII.Code(unchecked: byte)
            switch code {
            case .quotationMark:                 // " - closing quote
                scanner.advance()
                if isASCII {
                    let count = stringScratch.count
                    let result = stringScratch.withUnsafeBufferPointer { src -> String in
                        String(unsafeUninitializedCapacity: count) { dst in
                            if count > 0 {
                                dst.baseAddress!.update(from: src.baseAddress!, count: count)
                            }
                            return count
                        }
                    }
                    return result
                }
                return String(decoding: stringScratch, as: UTF8.self)

            case .reverseSlant:                  // \ - escape sequence
                scanner.advance()
                let escapeBytes = try lexEscapeSequence()
                for b in escapeBytes {
                    if b > 0x7F { isASCII = false }
                    stringScratch.append(b)
                }

            case .nul...ASCII.Code.us:           // Control characters (C0 range, 0x00...0x1F)
                throw .invalidString(at: currentPosition(), reason: .controlCharacter(code))

            default:
                // Printable 7-bit ASCII content (0x20...0x7F minus the cases above).
                stringScratch.append(code.underlying)
                scanner.advance()
            }
        }

        // Report the position at the start of the (now-unterminated) string.
        throw .invalidString(
            at: position(at: startCursor),
            reason: .unterminated
        )
    }

    /// Lexes an escape sequence after the backslash.
    @inlinable
    @_lifetime(self: copy self)
    internal mutating func lexEscapeSequence() throws(RFC_8259.Error) -> [UInt8] {
        // Type-up: lift to ASCII.Code at the peek boundary.
        guard let code: ASCII.Code = scanner.peek() else {
            throw .unexpectedEndOfInput(at: currentPosition(), expected: .value)
        }

        scanner.advance()

        switch code {
        case .quotationMark:  return [.ascii.quotationMark]   // \"
        case .reverseSlant:   return [.ascii.reverseSlant]    // \\
        case .solidus:        return [.ascii.solidus]         // \/
        case .b:              return [.ascii.bs]              // \b
        case .f:              return [.ascii.ff]              // \f
        case .n:              return [.ascii.lf]              // \n
        case .r:              return [.ascii.cr]              // \r
        case .t:              return [.ascii.htab]            // \t
        case .u:              return try lexUnicodeEscape()   // \uXXXX
        default:
            throw .invalidString(at: currentPosition(), reason: .invalidEscape(code))
        }
    }

    /// Lexes a \uXXXX Unicode escape.
    @inlinable
    @_lifetime(self: copy self)
    internal mutating func lexUnicodeEscape() throws(RFC_8259.Error) -> [UInt8] {
        var hex: [ASCII.Code] = []
        hex.reserveCapacity(4)

        for _ in 0..<4 {
            guard let code: ASCII.Code = scanner.peek() else {
                throw .invalidString(at: currentPosition(), reason: .invalidUnicodeEscape)
            }
            guard code.isHexDigit else {
                throw .invalidString(at: currentPosition(), reason: .invalidUnicodeEscape)
            }
            hex.append(code)
            scanner.advance()
        }

        guard let codePoint = parseHex(hex) else {
            throw .invalidString(at: currentPosition(), reason: .invalidUnicodeEscape)
        }

        // Handle surrogate pairs.
        if codePoint >= 0xD800 && codePoint <= 0xDBFF {
            guard let rs: ASCII.Code = scanner.peek(), rs == .reverseSlant else {
                throw .invalidString(at: currentPosition(), reason: .invalidUnicodeEscape)
            }
            scanner.advance()
            guard let u: ASCII.Code = scanner.peek(), u == .u else {
                throw .invalidString(at: currentPosition(), reason: .invalidUnicodeEscape)
            }
            scanner.advance()

            var lowHex: [ASCII.Code] = []
            lowHex.reserveCapacity(4)
            for _ in 0..<4 {
                guard let code: ASCII.Code = scanner.peek(), code.isHexDigit else {
                    throw .invalidString(at: currentPosition(), reason: .invalidUnicodeEscape)
                }
                lowHex.append(code)
                scanner.advance()
            }

            guard let lowCodePoint = parseHex(lowHex),
                  lowCodePoint >= 0xDC00 && lowCodePoint <= 0xDFFF else {
                throw .invalidString(at: currentPosition(), reason: .invalidUnicodeEscape)
            }

            let combined = 0x10000 + ((codePoint - 0xD800) << 10) + (lowCodePoint - 0xDC00)
            guard let combinedScalar = Unicode.Scalar(combined) else {
                throw .invalidString(at: currentPosition(), reason: .invalidUnicodeEscape)
            }
            return Swift.Array(String(combinedScalar).utf8)
        }

        guard let scalar = Unicode.Scalar(codePoint) else {
            throw .invalidString(at: currentPosition(), reason: .invalidUnicodeEscape)
        }
        return Swift.Array(String(scalar).utf8)
    }

    /// Parses 4 hex codes to a UInt32.
    @inlinable
    internal func parseHex(_ codes: [ASCII.Code]) -> UInt32? {
        guard codes.count == 4 else { return nil }
        var result: UInt32 = 0
        for code in codes {
            guard let digit = code.hexValue else { return nil }
            result = result * 16 + UInt32(digit)
        }
        return result
    }
}

// MARK: - Numbers

extension JSON.Decode.Implementation {
    /// Lexes a JSON number (called after the first byte has been
    /// peeked but NOT advanced). Returns `RFC_8259.Number` directly —
    /// no Token wrapping.
    @inlinable
    @_lifetime(self: copy self)
    internal mutating func lexNumberValue() throws(RFC_8259.Error) -> RFC_8259.Number {
        let startCursor = scanner.position
        var bytes = SmallByteArray(initialCapacity: Index<Byte>.Count(UInt(24)))

        // Optional minus
        // Type-up: lift to ASCII.Code at the peek boundary.
        if let b: ASCII.Code = scanner.peek(), b == .hyphen {
            bytes.append(scanner.consume())
        }

        // Integer part
        guard let firstDigit: ASCII.Code = scanner.peek(), firstDigit.isDigit else {
            throw .invalidNumber(
                at: position(at: startCursor),
                reason: .missingDigits(context: "integer part")
            )
        }

        if firstDigit == .`0` { // Leading zero
            bytes.append(scanner.consume())

            if let next: ASCII.Code = scanner.peek(), next.isDigit {
                throw .invalidNumber(
                    at: position(at: startCursor),
                    reason: .leadingZeros
                )
            }
        } else {
            while let code: ASCII.Code = scanner.peek(), code.isDigit {
                bytes.append(scanner.consume())
            }
        }

        var isFloat = false

        // Optional fraction
        if let b: ASCII.Code = scanner.peek(), b == .period {
            isFloat = true
            bytes.append(scanner.consume())

            guard let firstFracDigit: ASCII.Code = scanner.peek(), firstFracDigit.isDigit else {
                throw .invalidNumber(
                    at: position(at: startCursor),
                    reason: .missingDigits(context: "fraction")
                )
            }

            while let code: ASCII.Code = scanner.peek(), code.isDigit {
                bytes.append(scanner.consume())
            }
        }

        // Optional exponent
        if let e: ASCII.Code = scanner.peek(), e == .e || e == .E {
            isFloat = true
            bytes.append(scanner.consume())

            if let sign: ASCII.Code = scanner.peek(), sign == .plusSign || sign == .hyphen {
                bytes.append(scanner.consume())
            }

            guard let firstExpDigit: ASCII.Code = scanner.peek(), firstExpDigit.isDigit else {
                throw .invalidNumber(
                    at: position(at: startCursor),
                    reason: .missingDigits(context: "exponent")
                )
            }

            while let code: ASCII.Code = scanner.peek(), code.isDigit {
                bytes.append(scanner.consume())
            }
        }

        // Hot path: build `Original` directly from the inline-storage
        // span (no intermediate `Swift.Array`). Float branch parses
        // off the span via Eisel–Lemire — no `numStr` allocation.
        // Integer branch keeps `numStr` for Int64/UInt64 parsing.
        // See parse-performance-canada-anomaly.md v1.1.0.
        let span = bytes.span
        let original = RFC_8259.Number.Original(span)

        if isFloat {
            let value: Double
            do {
                value = try ASCII.Decimal.Float.parse(span)
            } catch {
                throw .invalidNumber(
                    at: position(at: startCursor),
                    reason: .overflow
                )
            }
            guard value.isFinite else {
                throw .invalidNumber(
                    at: position(at: startCursor),
                    reason: .overflow
                )
            }
            return RFC_8259.Number(value, original: original)
        } else {
            // Stdlib boundary: String.init(unsafeUninitializedCapacity:)
            // takes UnsafeMutableBufferPointer<UInt8>. Read Byte's
            // underlying UInt8 at each slot — the only legitimate use of
            // `.underlying` per W2 byte-cascade discipline (stdlib edge).
            let numStr = String(unsafeUninitializedCapacity: span.count) { dst in
                for i in 0..<span.count {
                    dst[i] = span[i].underlying
                }
                return span.count
            }
            if let value = Int64(numStr) {
                return RFC_8259.Number(value, original: original)
            } else if let value = UInt64(numStr) {
                return RFC_8259.Number(value, original: original)
            } else if let value = Double(numStr), value.isFinite {
                return RFC_8259.Number(value, original: original)
            } else {
                throw .invalidNumber(
                    at: position(at: startCursor),
                    reason: .overflow
                )
            }
        }
    }
}
