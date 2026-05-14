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
public import RFC_8259

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
    scanner.advance() // Consume opening `"`.

    scratch.removeAll(keepingCapacity: true)
    var isASCII = true

    while let byte = scanner.peek() {
        switch byte {
        case UInt8.ascii.quotationMark:
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
        case UInt8.ascii.reverseSlant:
            scanner.advance()
            let escapeBytes = try _lexEscape(scanner: &scanner)
            for b in escapeBytes {
                if b > 0x7F { isASCII = false }
                scratch.append(b)
            }
        case 0x00...0x1F:
            throw .invalidString(
                at: _position(at: scanner.position, scanner: scanner),
                reason: .controlCharacter(byte)
            )
        default:
            if byte > 0x7F { isASCII = false }
            scratch.append(byte)
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
    guard let byte = scanner.peek() else {
        throw .unexpectedEndOfInput(
            at: _position(at: scanner.position, scanner: scanner),
            expected: .value
        )
    }
    scanner.advance()
    switch byte {
    case UInt8.ascii.quotationMark:  return [.ascii.quotationMark]
    case UInt8.ascii.reverseSlant:   return [.ascii.reverseSlant]
    case UInt8.ascii.solidus:        return [.ascii.solidus]
    case UInt8.ascii.b:              return [.ascii.bs]
    case UInt8.ascii.f:              return [.ascii.ff]
    case UInt8.ascii.n:              return [.ascii.lf]
    case UInt8.ascii.r:              return [.ascii.cr]
    case UInt8.ascii.t:              return [.ascii.htab]
    case UInt8.ascii.u:              return try _lexUnicodeEscape(scanner: &scanner)
    default:
        throw .invalidString(
            at: _position(at: scanner.position, scanner: scanner),
            reason: .invalidEscape(byte)
        )
    }
}

@inlinable
internal func _lexUnicodeEscape(
    scanner: inout Lexer.Scanner
) throws(RFC_8259.Error) -> [UInt8] {
    var hex: [UInt8] = []
    hex.reserveCapacity(4)

    for _ in 0..<4 {
        guard let byte = scanner.peek() else {
            throw .invalidString(
                at: _position(at: scanner.position, scanner: scanner),
                reason: .invalidUnicodeEscape
            )
        }
        guard byte.ascii.isHexDigit else {
            throw .invalidString(
                at: _position(at: scanner.position, scanner: scanner),
                reason: .invalidUnicodeEscape
            )
        }
        hex.append(byte)
        scanner.advance()
    }

    guard let codePoint = _parseHex(hex) else {
        throw .invalidString(
            at: _position(at: scanner.position, scanner: scanner),
            reason: .invalidUnicodeEscape
        )
    }

    if codePoint >= 0xD800 && codePoint <= 0xDBFF {
        guard scanner.peek() == UInt8.ascii.reverseSlant else {
            throw .invalidString(
                at: _position(at: scanner.position, scanner: scanner),
                reason: .invalidUnicodeEscape
            )
        }
        scanner.advance()
        guard scanner.peek() == UInt8.ascii.u else {
            throw .invalidString(
                at: _position(at: scanner.position, scanner: scanner),
                reason: .invalidUnicodeEscape
            )
        }
        scanner.advance()

        var lowHex: [UInt8] = []
        lowHex.reserveCapacity(4)
        for _ in 0..<4 {
            guard let byte = scanner.peek(), byte.ascii.isHexDigit else {
                throw .invalidString(
                    at: _position(at: scanner.position, scanner: scanner),
                    reason: .invalidUnicodeEscape
                )
            }
            lowHex.append(byte)
            scanner.advance()
        }

        guard let lowCodePoint = _parseHex(lowHex),
              lowCodePoint >= 0xDC00 && lowCodePoint <= 0xDFFF else {
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
internal func _parseHex(_ bytes: [UInt8]) -> UInt32? {
    guard bytes.count == 4 else { return nil }
    var result: UInt32 = 0
    for byte in bytes {
        guard let digit = byte.ascii.hexValue else { return nil }
        result = result * 16 + UInt32(digit)
    }
    return result
}

@inlinable
internal func _lexNumber(
    scanner: inout Lexer.Scanner
) throws(RFC_8259.Error) -> RFC_8259.Number {
    let startCursor = scanner.position
    var bytes = Array_Primitives.Array<UInt8>.Small<24>()

    // Optional minus.
    if scanner.peek() == UInt8.ascii.hyphen {
        bytes.append(scanner.consume())
    }

    // Integer part.
    guard let firstDigit = scanner.peek(), firstDigit.ascii.isDigit else {
        throw .invalidNumber(
            at: _position(at: startCursor, scanner: scanner),
            reason: .missingDigits(context: "integer part")
        )
    }
    if firstDigit == UInt8.ascii.`0` {
        bytes.append(scanner.consume())
        if let next = scanner.peek(), next.ascii.isDigit {
            throw .invalidNumber(
                at: _position(at: startCursor, scanner: scanner),
                reason: .leadingZeros
            )
        }
    } else {
        while let byte = scanner.peek(), byte.ascii.isDigit {
            bytes.append(scanner.consume())
        }
    }

    var isFloat = false

    // Optional fraction.
    if scanner.peek() == UInt8.ascii.period {
        isFloat = true
        bytes.append(scanner.consume())
        guard let firstFracDigit = scanner.peek(), firstFracDigit.ascii.isDigit else {
            throw .invalidNumber(
                at: _position(at: startCursor, scanner: scanner),
                reason: .missingDigits(context: "fraction")
            )
        }
        while let byte = scanner.peek(), byte.ascii.isDigit {
            bytes.append(scanner.consume())
        }
    }

    // Optional exponent.
    if let e = scanner.peek(), e == UInt8.ascii.e || e == UInt8.ascii.E {
        isFloat = true
        bytes.append(scanner.consume())
        if let sign = scanner.peek(), sign == UInt8.ascii.plusSign || sign == UInt8.ascii.hyphen {
            bytes.append(scanner.consume())
        }
        guard let firstExpDigit = scanner.peek(), firstExpDigit.ascii.isDigit else {
            throw .invalidNumber(
                at: _position(at: startCursor, scanner: scanner),
                reason: .missingDigits(context: "exponent")
            )
        }
        while let byte = scanner.peek(), byte.ascii.isDigit {
            bytes.append(scanner.consume())
        }
    }

    let span = bytes.span
    let byteArray: [UInt8] = .init(unsafeUninitializedCapacity: span.count) { dst, initialized in
        for i in 0..<span.count {
            dst[i] = span[i]
        }
        initialized = span.count
    }
    let original = RFC_8259.Number.Original(byteArray)
    let numStr = String(decoding: byteArray, as: UTF8.self)

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
