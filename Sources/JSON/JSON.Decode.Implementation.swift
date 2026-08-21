public import ASCII_Decimal_Parser_Primitives
@_spi(Unsafe) public import Array_Primitives
public import Buffer_Linear_Primitive
public import Buffer_Linear_Primitives
public import Buffer_Primitive
public import Byte_Primitive
public import Index_Primitives
public import Lexer_Primitives
public import Memory_Allocator_Primitive
public import Memory_Small_Primitives
public import RFC_8259
public import Storage_Contiguous_Primitives
public import Storage_Primitive

extension JSON.Decode {

    @safe
    @usableFromInline
    internal struct Implementation: ~Copyable, ~Escapable {
        @usableFromInline
        internal var scanner: Lexer_Primitives.Lexer.Scanner

        @usableFromInline
        internal var depth: Int

        @usableFromInline
        internal let maxDepth: Int

        @usableFromInline
        internal var stringScratch: [UInt8]

        @inlinable
        @_lifetime(borrow bytes)
        package init(_ bytes: borrowing Swift.Span<Byte>, maxDepth: Int) {
            self.scanner = Lexer_Primitives.Lexer.Scanner(bytes)
            self.depth = 0
            self.maxDepth = maxDepth
            var scratch: [UInt8] = []
            scratch.reserveCapacity(64)
            self.stringScratch = scratch
        }
    }
}

extension JSON.Decode.Implementation {

    @inlinable
    package static func parse(
        _ bytes: borrowing Swift.Span<Byte>,
        maxDepth: Int
    ) throws(RFC_8259.Error) -> RFC_8259.Value {
        var parser = JSON.Decode.Implementation(bytes, maxDepth: maxDepth)
        return try parser.parse()
    }

    @inlinable
    @_lifetime(self: copy self)
    package mutating func parse() throws(RFC_8259.Error) -> RFC_8259.Value {
        let value = try parseValue()

        skipWhitespace()
        if !scanner.isAtEnd {
            throw .trailingContent(at: currentPosition())
        }

        return value
    }
}

extension JSON.Decode.Implementation {

    @inlinable
    package func currentPosition() -> RFC_8259.Position {
        let pos = scanner.position
        return RFC_8259.Position(offset: pos, location: scanner.location(at: pos))
    }

    @inlinable
    package func position(at cursor: Text.Position) -> RFC_8259.Position {
        RFC_8259.Position(offset: cursor, location: scanner.location(at: cursor))
    }
}

extension JSON.Decode.Implementation {

    @inlinable
    @_lifetime(self: copy self)
    package mutating func parseValue() throws(RFC_8259.Error) -> RFC_8259.Value {
        skipWhitespace()

        guard let code: ASCII.Code = scanner.peek() else {
            throw .unexpectedEndOfInput(at: currentPosition(), expected: .value)
        }

        switch code {
        case .leftBrace:
            scanner.advance()
            return try parseObject()

        case .leftBracket:
            scanner.advance()
            return try parseArray()

        case .quotationMark:
            let s = try lexStringValue()
            return .string(s)

        case .n:
            try expectLiteral([.n, .u, .l, .l])
            return .null

        case .t:
            try expectLiteral([.t, .r, .u, .e])
            return .bool(true)

        case .f:
            try expectLiteral([.f, .a, .l, .s, .e])
            return .bool(false)

        case .hyphen,
            .`0`...ASCII.Code.`9`:
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

extension JSON.Decode.Implementation {
    @inlinable
    @_lifetime(self: copy self)
    package mutating func parseArray() throws(RFC_8259.Error) -> RFC_8259.Value {
        depth += 1
        if depth > maxDepth {
            throw .depthExceeded(at: currentPosition(), limit: maxDepth)
        }
        defer { depth -= 1 }

        var elements: [RFC_8259.Value] = []

        elements.reserveCapacity(4)

        skipWhitespace()

        if let code: ASCII.Code = scanner.peek(), code == .rightBracket {
            scanner.advance()
            return .array(RFC_8259.Array(elements))
        }

        elements.append(try parseValue())

        while true {
            skipWhitespace()

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

extension JSON.Decode.Implementation {
    @inlinable
    @_lifetime(self: copy self)
    package mutating func parseObject() throws(RFC_8259.Error) -> RFC_8259.Value {
        depth += 1
        if depth > maxDepth {
            throw .depthExceeded(at: currentPosition(), limit: maxDepth)
        }
        defer { depth -= 1 }

        var members: [(key: String, value: RFC_8259.Value)] = []

        skipWhitespace()

        if let code: ASCII.Code = scanner.peek(), code == .rightBrace {
            scanner.advance()
            return .object(RFC_8259.Object(members))
        }

        members.append(try parseMember())

        while true {
            skipWhitespace()

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

    @inlinable
    @_lifetime(self: copy self)
    package mutating func parseMember() throws(RFC_8259.Error) -> (
        key: String, value: RFC_8259.Value
    ) {
        skipWhitespace()

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

        let value = try parseValue()
        return (key: key, value: value)
    }
}

extension JSON.Decode.Implementation {

    @inlinable
    @_lifetime(self: copy self)
    package mutating func skipWhitespace() {
        while let byte = scanner.peek() {

            switch byte {
            case 0x20, 0x09, 0x0A, 0x0D:
                scanner.advance()

            default:
                return
            }
        }
    }
}

extension JSON.Decode.Implementation {

    @inlinable
    @_lifetime(self: copy self)
    package mutating func expectLiteral(_ expected: [ASCII.Code]) throws(RFC_8259.Error) {
        let startCursor = scanner.position
        for expectedCode in expected {

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

extension JSON.Decode.Implementation {

    @inlinable
    @_lifetime(self: copy self)
    package mutating func lexStringValue() throws(RFC_8259.Error) -> String {
        let startCursor = scanner.position

        scanner.advance()

        stringScratch.removeAll(keepingCapacity: true)
        var isASCII = true

        while let byte: Byte = scanner.peek() {
            guard byte.underlying < 0x80 else {

                isASCII = false
                stringScratch.append(byte.underlying)
                scanner.advance()
                continue
            }

            let code = ASCII.Code(unchecked: byte)
            switch code {
            case .quotationMark:
                scanner.advance()
                if isASCII {
                    let count = stringScratch.count
                    return stringScratch.withUnsafeBufferPointer { src -> String in
                        String(unsafeUninitializedCapacity: count) { dst in
                            if count > 0 {
                                unsafe dst.baseAddress!.update(from: src.baseAddress!, count: count)
                            }
                            return count
                        }
                    }
                }
                return String(decoding: stringScratch, as: UTF8.self)

            case .reverseSlant:
                scanner.advance()
                let escapeBytes = try lexEscapeSequence()
                for b in escapeBytes {
                    if b > 0x7F { isASCII = false }
                    stringScratch.append(b)
                }

            case .nul...ASCII.Code.us:
                throw .invalidString(at: currentPosition(), reason: .controlCharacter(code))

            default:

                stringScratch.append(code.underlying)
                scanner.advance()
            }
        }

        throw .invalidString(
            at: position(at: startCursor),
            reason: .unterminated
        )
    }

    @inlinable
    @_lifetime(self: copy self)
    package mutating func lexEscapeSequence() throws(RFC_8259.Error) -> [UInt8] {

        guard let code: ASCII.Code = scanner.peek() else {
            throw .unexpectedEndOfInput(at: currentPosition(), expected: .value)
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
        case .u: return try lexUnicodeEscape()

        default:
            throw .invalidString(at: currentPosition(), reason: .invalidEscape(code))
        }
    }

    @inlinable
    @_lifetime(self: copy self)
    package mutating func lexUnicodeEscape() throws(RFC_8259.Error) -> [UInt8] {
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
                lowCodePoint >= 0xDC00 && lowCodePoint <= 0xDFFF
            else {
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

    @inlinable
    package func parseHex(_ codes: [ASCII.Code]) -> UInt32? {
        guard codes.count == 4 else { return nil }
        var result: UInt32 = 0
        for code in codes {
            guard let digit = code.hexValue else { return nil }
            result = result * 16 + UInt32(digit)
        }
        return result
    }
}

extension JSON.Decode.Implementation {

    @inlinable
    @_lifetime(self: copy self)
    package mutating func lexNumberValue() throws(RFC_8259.Error) -> RFC_8259.Number {
        let startCursor = scanner.position
        var bytes = SmallByteArray(initialCapacity: Index<Byte>.Count(UInt(24)))

        if let b: ASCII.Code = scanner.peek(), b == .hyphen {
            bytes.append(scanner.consume())
        }

        guard let firstDigit: ASCII.Code = scanner.peek(), firstDigit.isDigit else {
            throw .invalidNumber(
                at: position(at: startCursor),
                reason: .missingDigits(context: "integer part")
            )
        }

        if firstDigit == .`0` {
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

        let span = bytes.span
        let original = RFC_8259.Number.Original(span)

        if isFloat {
            let value: Double
            do throws(ASCII.Decimal.Float.Error) {
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

            let numStr = original.string
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
