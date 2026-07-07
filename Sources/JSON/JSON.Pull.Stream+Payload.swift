/// JSON.Pull.Stream+Payload.swift
/// swift-json
///
/// JSON-specific payload-decode methods for the L1 generic stream
/// specialised to ``RFC_8259/Pull/Tokens``.
///
/// Public surface: extensions on
/// `Lexer.Pull.Stream where Tokens == RFC_8259.Pull.Tokens` adding
/// ``currentString()`` and ``currentNumber()``.
///
/// The internal lex helpers (`_lexString`, `_lexEscape`,
/// `_lexUnicodeEscape`, `_parseHex`, `_lexNumber`, `_position`) are
/// declared as module-scope `@inlinable internal` free functions
/// — NOT as extensions on `RFC_8259.Pull.Tokens` — per Arc 1.6
/// namespace correction: the spec witness namespace must host SPEC
/// content only.

@_spi(Unsafe) public import Array_Primitives
public import Array_Small_Primitive
public import Buffer_Linear_Primitive
public import Buffer_Linear_Primitives
// The small-column tower must be `public import`: the lexer helpers below are `@inlinable`, so the
// column's conformances (`Memory.Small: Growable`, `Storage.Contiguous: Store.Protocol`,
// `Buffer.Linear: Buffer.Protocol`) have to be visible to inlined clients ([MemberImportVisibility]).
// This matches the existing `Array_Primitives` public import; the JSON public API surface
// (`currentNumber()` → `RFC_8259.Number`) is unchanged.
public import Buffer_Primitive
public import Byte_Primitive
public import Index_Primitives
public import Memory_Allocator_Primitive
public import Memory_Small_Primitives
public import RFC_8259
public import Storage_Contiguous_Primitives
public import Storage_Primitive

/// The number-lexer scratch accumulator: the move-only **small column** (`Memory.Small<24>`) of the
/// `Array<S>`-over-column tower — the inline⊕heap SBO that restores the original
/// `Array<Byte>.Small<24>` behaviour: a JSON number up to 24 bytes accumulates entirely inline (no
/// heap allocation — the common case), and longer numbers spill transparently to a heap region
/// (valid JSON may exceed 24 bytes — it never traps). `init(initialCapacity:)` sizes the inline
/// budget. This is the principled spelling now that `Storage.Contiguous` derives its typed base per
/// access ([MEM-SAFE-029]) — the small column's inline arm moves its bytes with the value, which the
/// per-access base derivation tracks correctly (the prior cached-base shape corrupted on the first
/// move, which is why this scratch buffer was temporarily spelled as the always-heap column).
///
/// `@usableFromInline` (not `private`): referenced by the `@inlinable` lexer helpers below.
@usableFromInline
typealias SmallByteArray = Array<Byte>.Small<24>

// MARK: - Public payload-decode methods on the generic stream

extension Lexer.Pull.Stream where Tokens == RFC_8259.Pull.Tokens {
    /// Decode the string at the current position. Call after
    /// `next()` returned `.string` and BEFORE any subsequent
    /// `next()` / `skip()` call.
    ///
    /// Reuses the stream's `scratch` buffer; handles RFC 8259 §7
    /// escape sequences including surrogate pairs.
    @inlinable
    @_lifetime(self: copy self)
    public mutating func currentString() throws(RFC_8259.Error) -> String {
        touch()
        return try _lexString(scanner: &scanner, scratch: &scratch)
    }

    /// Decode the number at the current position. Call after
    /// `next()` returned `.number`.
    ///
    /// Handles RFC 8259 §6 number grammar (sign, leading-zero rule,
    /// optional fraction, optional exponent) and chooses Int64 /
    /// UInt64 / Double materialisation.
    @inlinable
    @_lifetime(self: copy self)
    public mutating func currentNumber() throws(RFC_8259.Error) -> RFC_8259.Number {
        touch()
        return try _lexNumber(scanner: &scanner)
    }
}

// MARK: - Module-scope position helper

/// Builds `RFC_8259.Position` from a cursor + scanner. Module-scope
/// free function (not an extension on the spec witness) — see file
/// header.
@inlinable
internal func _position(
    at cursor: Text.Position,
    scanner: borrowing Lexer.Scanner
) -> RFC_8259.Position {
    RFC_8259.Position(offset: cursor, location: scanner.location(at: cursor))
}

// MARK: - Module-scope lex helpers (free functions, not extensions)

@inlinable
internal func _lexString(
    scanner: inout Lexer.Scanner,
    scratch: inout [UInt8]
) throws(RFC_8259.Error) -> String {
    let startCursor = scanner.position
    scanner.advance()  // Consume opening `"`.

    scratch.removeAll(keepingCapacity: true)
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
            scratch.append(byte.underlying)
            scanner.advance()
            continue
        }
        // In range: lift unchecked (the guard above IS the throwing
        // init's validation) so the structural cases match ASCII.Code
        // constants directly.
        let code = ASCII.Code(unchecked: byte)
        switch code {
        case .quotationMark:
            scanner.advance()
            if isASCII {
                let count = scratch.count
                let result = scratch.withUnsafeBufferPointer { src -> String in
                    String(unsafeUninitializedCapacity: count) { dst in
                        if count > 0 {
                            dst.baseAddress!.update(from: src.baseAddress!, count: count)
                        }
                        return count
                    }
                }
                return result
            }
            return String(decoding: scratch, as: UTF8.self)
        case .reverseSlant:
            scanner.advance()
            let escapeBytes = try _lexEscape(scanner: &scanner)
            for b in escapeBytes {
                if b > 0x7F { isASCII = false }
                scratch.append(b)
            }
        case .nul...ASCII.Code.us:  // 0x00...0x1F (per ASCII.Code Control range)
            throw .invalidString(
                at: _position(at: scanner.position, scanner: scanner),
                reason: .controlCharacter(code)
            )
        default:
            // Printable 7-bit ASCII content (0x20...0x7F minus the cases above).
            scratch.append(code.underlying)
            scanner.advance()
        }
    }

    throw .invalidString(
        at: _position(at: startCursor, scanner: scanner),
        reason: .unterminated
    )
}

@inlinable
internal func _lexEscape(
    scanner: inout Lexer.Scanner
) throws(RFC_8259.Error) -> [UInt8] {
    // Type-up: lift to ASCII.Code at the peek boundary.
    guard let code: ASCII.Code = scanner.peek() else {
        throw .unexpectedEndOfInput(
            at: _position(at: scanner.position, scanner: scanner),
            expected: .value
        )
    }
    scanner.advance()
    switch code {
    case .quotationMark: return [.ascii.quotationMark]
    case .reverseSlant: return [.ascii.reverseSlant]
    case .solidus: return [.ascii.solidus]
    case .b: return [.ascii.bs]
    case .f: return [.ascii.ff]
    case .n: return [.ascii.lf]
    case .r: return [.ascii.cr]
    case .t: return [.ascii.htab]
    case .u: return try _lexUnicodeEscape(scanner: &scanner)
    default:
        throw .invalidString(
            at: _position(at: scanner.position, scanner: scanner),
            reason: .invalidEscape(code)
        )
    }
}

@inlinable
internal func _lexUnicodeEscape(
    scanner: inout Lexer.Scanner
) throws(RFC_8259.Error) -> [UInt8] {
    var hex: [ASCII.Code] = []
    hex.reserveCapacity(4)

    for _ in 0..<4 {
        guard let code: ASCII.Code = scanner.peek() else {
            throw .invalidString(
                at: _position(at: scanner.position, scanner: scanner),
                reason: .invalidUnicodeEscape
            )
        }
        guard code.isHexDigit else {
            throw .invalidString(
                at: _position(at: scanner.position, scanner: scanner),
                reason: .invalidUnicodeEscape
            )
        }
        hex.append(code)
        scanner.advance()
    }

    guard let codePoint = _parseHex(hex) else {
        throw .invalidString(
            at: _position(at: scanner.position, scanner: scanner),
            reason: .invalidUnicodeEscape
        )
    }

    if codePoint >= 0xD800 && codePoint <= 0xDBFF {
        guard let rs: ASCII.Code = scanner.peek(), rs == .reverseSlant else {
            throw .invalidString(
                at: _position(at: scanner.position, scanner: scanner),
                reason: .invalidUnicodeEscape
            )
        }
        scanner.advance()
        guard let u: ASCII.Code = scanner.peek(), u == .u else {
            throw .invalidString(
                at: _position(at: scanner.position, scanner: scanner),
                reason: .invalidUnicodeEscape
            )
        }
        scanner.advance()

        var lowHex: [ASCII.Code] = []
        lowHex.reserveCapacity(4)
        for _ in 0..<4 {
            guard let code: ASCII.Code = scanner.peek(), code.isHexDigit else {
                throw .invalidString(
                    at: _position(at: scanner.position, scanner: scanner),
                    reason: .invalidUnicodeEscape
                )
            }
            lowHex.append(code)
            scanner.advance()
        }

        guard let lowCodePoint = _parseHex(lowHex),
            lowCodePoint >= 0xDC00 && lowCodePoint <= 0xDFFF
        else {
            throw .invalidString(
                at: _position(at: scanner.position, scanner: scanner),
                reason: .invalidUnicodeEscape
            )
        }

        let combined = 0x10000 + ((codePoint - 0xD800) << 10) + (lowCodePoint - 0xDC00)
        guard let combinedScalar = Unicode.Scalar(combined) else {
            throw .invalidString(
                at: _position(at: scanner.position, scanner: scanner),
                reason: .invalidUnicodeEscape
            )
        }
        return Swift.Array(String(combinedScalar).utf8)
    }

    guard let scalar = Unicode.Scalar(codePoint) else {
        throw .invalidString(
            at: _position(at: scanner.position, scanner: scanner),
            reason: .invalidUnicodeEscape
        )
    }
    return Swift.Array(String(scalar).utf8)
}

@inlinable
internal func _parseHex(_ codes: [ASCII.Code]) -> UInt32? {
    guard codes.count == 4 else { return nil }
    var result: UInt32 = 0
    for code in codes {
        guard let digit = code.hexValue else { return nil }
        result = result * 16 + UInt32(digit)
    }
    return result
}

@inlinable
internal func _lexNumber(
    scanner: inout Lexer.Scanner
) throws(RFC_8259.Error) -> RFC_8259.Number {
    let startCursor = scanner.position
    var bytes = SmallByteArray(store: .init(minimumCapacity: Index<Byte>.Count(24)))

    // Optional minus.
    if let b: ASCII.Code = scanner.peek(), b == .hyphen {
        bytes.append(scanner.consume())
    }

    // Integer part.
    guard let firstDigit: ASCII.Code = scanner.peek(), firstDigit.isDigit else {
        throw .invalidNumber(
            at: _position(at: startCursor, scanner: scanner),
            reason: .missingDigits(context: "integer part")
        )
    }
    if firstDigit == .`0` {
        bytes.append(scanner.consume())
        if let next: ASCII.Code = scanner.peek(), next.isDigit {
            throw .invalidNumber(
                at: _position(at: startCursor, scanner: scanner),
                reason: .leadingZeros
            )
        }
    } else {
        while let code: ASCII.Code = scanner.peek(), code.isDigit {
            bytes.append(scanner.consume())
        }
    }

    var isFloat = false

    // Optional fraction.
    if let b: ASCII.Code = scanner.peek(), b == .period {
        isFloat = true
        bytes.append(scanner.consume())
        guard let firstFracDigit: ASCII.Code = scanner.peek(), firstFracDigit.isDigit else {
            throw .invalidNumber(
                at: _position(at: startCursor, scanner: scanner),
                reason: .missingDigits(context: "fraction")
            )
        }
        while let code: ASCII.Code = scanner.peek(), code.isDigit {
            bytes.append(scanner.consume())
        }
    }

    // Optional exponent.
    if let e: ASCII.Code = scanner.peek(), e == .e || e == .E {
        isFloat = true
        bytes.append(scanner.consume())
        if let sign: ASCII.Code = scanner.peek(), sign == .plusSign || sign == .hyphen {
            bytes.append(scanner.consume())
        }
        guard let firstExpDigit: ASCII.Code = scanner.peek(), firstExpDigit.isDigit else {
            throw .invalidNumber(
                at: _position(at: startCursor, scanner: scanner),
                reason: .missingDigits(context: "exponent")
            )
        }
        while let code: ASCII.Code = scanner.peek(), code.isDigit {
            bytes.append(scanner.consume())
        }
    }

    let span = bytes.span
    // Build [Byte] for Number.Original; UInt8 mirror for stdlib's
    // Double(_:String) / Int64.init(_:String) at the numStr stdlib edge.
    let byteArray: [Byte] = .init(unsafeUninitializedCapacity: span.count) { dst, initialized in
        for i in 0..<span.count {
            dst[i] = span[i]
        }
        initialized = span.count
    }
    let original = RFC_8259.Number.Original(byteArray)
    let numStr = String(decoding: byteArray.lazy.map(\.underlying), as: UTF8.self)

    if isFloat {
        guard let value = Double(numStr), value.isFinite else {
            throw .invalidNumber(
                at: _position(at: startCursor, scanner: scanner),
                reason: .overflow
            )
        }
        return RFC_8259.Number(value, original: original)
    } else {
        if let value = Int64(numStr) {
            return RFC_8259.Number(value, original: original)
        } else if let value = UInt64(numStr) {
            return RFC_8259.Number(value, original: original)
        } else if let value = Double(numStr), value.isFinite {
            return RFC_8259.Number(value, original: original)
        } else {
            throw .invalidNumber(
                at: _position(at: startCursor, scanner: scanner),
                reason: .overflow
            )
        }
    }
}
