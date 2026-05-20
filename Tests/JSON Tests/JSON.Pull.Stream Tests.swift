/// JSON.Pull.Stream Tests.swift
/// swift-json
///
/// Tests for `Lexer.Pull.Stream<RFC_8259.Pull.Tokens>` — the JSON
/// specialisation of the L1 pull-driven event cursor. The
/// JSON-specific payload-decode methods (`currentString`,
/// `currentNumber`) are defined as extensions at L3 in
/// `JSON.Pull.Stream+Payload.swift`; this suite exercises them
/// together with the L1 generic event stream.
///
/// Relocated from swift-rfc-8259/Tests under Arc 1.5 — the methods
/// being tested are implementation, not spec, so the tests live at L3.

import Testing
@testable import JSON

extension RFC_8259.Pull.Tokens {
@Suite("JSON Pull Stream Tests")
struct Tests {

    // MARK: - Token.Kind emission

    @Test
    func `next emits objectStart and objectEnd for empty object`() throws {
        let bytes: [UInt8] = Swift.Array("{}".utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(try stream.next() == .objectStart)
            #expect(try stream.next() == .objectEnd)
            #expect(try stream.next() == nil)
        }
    }

    @Test
    func `next emits arrayStart and arrayEnd for empty array`() throws {
        let bytes: [UInt8] = Swift.Array("[]".utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(try stream.next() == .arrayStart)
            #expect(try stream.next() == .arrayEnd)
            #expect(try stream.next() == nil)
        }
    }

    @Test
    func `next emits comma colon string number sequence`() throws {
        let bytes: [UInt8] = Swift.Array(#"{"a":1,"b":2}"#.utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(try stream.next() == .objectStart)
            #expect(try stream.next() == .string)
            #expect(try stream.currentString() == "a")
            #expect(try stream.next() == .colon)
            #expect(try stream.next() == .number)
            #expect(try stream.currentNumber().int64 == 1)
            #expect(try stream.next() == .comma)
            #expect(try stream.next() == .string)
            #expect(try stream.currentString() == "b")
            #expect(try stream.next() == .colon)
            #expect(try stream.next() == .number)
            #expect(try stream.currentNumber().int64 == 2)
            #expect(try stream.next() == .objectEnd)
        }
    }

    @Test
    func `next emits null`() throws {
        let bytes: [UInt8] = Swift.Array("null".utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(try stream.next() == .null)
            #expect(try stream.next() == nil)
        }
    }

    @Test
    func `next emits true`() throws {
        let bytes: [UInt8] = Swift.Array("true".utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(try stream.next() == .`true`)
        }
    }

    @Test
    func `next emits false`() throws {
        let bytes: [UInt8] = Swift.Array("false".utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(try stream.next() == .`false`)
        }
    }

    // MARK: - currentString

    @Test
    func `currentString decodes ASCII payload`() throws {
        let bytes: [UInt8] = Swift.Array(#""hello""#.utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(try stream.next() == .string)
            #expect(try stream.currentString() == "hello")
        }
    }

    @Test
    func `currentString decodes escape sequences`() throws {
        let bytes: [UInt8] = Swift.Array(#""a\nb\tc\"d""#.utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(try stream.next() == .string)
            #expect(try stream.currentString() == "a\nb\tc\"d")
        }
    }

    @Test
    func `currentString decodes unicode escape`() throws {
        let bytes: [UInt8] = Swift.Array(#""é""#.utf8) // é
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(try stream.next() == .string)
            #expect(try stream.currentString() == "é")
        }
    }

    @Test
    func `currentString decodes surrogate pair`() throws {
        // U+1F600 (😀) encoded as surrogate pair 😀
        let bytes: [UInt8] = Swift.Array(#""😀""#.utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(try stream.next() == .string)
            #expect(try stream.currentString() == "😀")
        }
    }

    // MARK: - currentNumber

    @Test
    func `currentNumber decodes integer`() throws {
        let bytes: [UInt8] = Swift.Array("42".utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(try stream.next() == .number)
            #expect(try stream.currentNumber().int64 == 42)
        }
    }

    @Test
    func `currentNumber decodes negative integer`() throws {
        let bytes: [UInt8] = Swift.Array("-123".utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(try stream.next() == .number)
            #expect(try stream.currentNumber().int64 == -123)
        }
    }

    @Test
    func `currentNumber decodes floating point`() throws {
        let bytes: [UInt8] = Swift.Array("3.14".utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(try stream.next() == .number)
            #expect(try stream.currentNumber().double == 3.14)
        }
    }

    @Test
    func `currentNumber decodes scientific notation`() throws {
        let bytes: [UInt8] = Swift.Array("1.5e10".utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(try stream.next() == .number)
            #expect(try stream.currentNumber().double == 1.5e10)
        }
    }

    // MARK: - isPristine

    @Test
    func `isPristine true at init`() throws {
        let bytes: [UInt8] = Swift.Array(#"{"a":1}"#.utf8)
        bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) in
            let span = buf.span
            let stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(stream.isPristine == true)
        }
    }

    @Test
    func `isPristine false after next`() throws {
        let bytes: [UInt8] = Swift.Array(#"{"a":1}"#.utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(stream.isPristine == true)
            _ = try stream.next()
            #expect(stream.isPristine == false)
        }
    }

    @Test
    func `isPristine false after skipValue`() throws {
        let bytes: [UInt8] = Swift.Array(#"{"a":1}"#.utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(stream.isPristine == true)
            try stream.skip()
            #expect(stream.isPristine == false)
        }
    }

    // MARK: - skipValue

    @Test
    func `skipValue skips a string`() throws {
        let bytes: [UInt8] = Swift.Array(#""skip me",42"#.utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            try stream.skip()
            #expect(try stream.next() == .comma)
            #expect(try stream.next() == .number)
            #expect(try stream.currentNumber().int64 == 42)
        }
    }

    @Test
    func `skipValue skips a number`() throws {
        let bytes: [UInt8] = Swift.Array(#"3.14,"after""#.utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            try stream.skip()
            #expect(try stream.next() == .comma)
            #expect(try stream.next() == .string)
            #expect(try stream.currentString() == "after")
        }
    }

    @Test
    func `skipValue skips a literal`() throws {
        let bytes: [UInt8] = Swift.Array(#"null,true,false,42"#.utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            try stream.skip() // null
            #expect(try stream.next() == .comma)
            try stream.skip() // true
            #expect(try stream.next() == .comma)
            try stream.skip() // false
            #expect(try stream.next() == .comma)
            #expect(try stream.next() == .number)
            #expect(try stream.currentNumber().int64 == 42)
        }
    }

    @Test
    func `skipValue skips a nested object`() throws {
        let bytes: [UInt8] = Swift.Array(#"{"nested":{"a":1,"b":[1,2,3]}},42"#.utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            try stream.skip() // skips the whole {...}
            #expect(try stream.next() == .comma)
            #expect(try stream.next() == .number)
            #expect(try stream.currentNumber().int64 == 42)
        }
    }

    @Test
    func `skipValue inside object skips remaining members`() throws {
        // After consuming objectStart, skipValue should walk to the
        // matching objectEnd.
        let bytes: [UInt8] = Swift.Array(#"{"a":1,"b":2,"c":3},42"#.utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(try stream.next() == .objectStart)
            // Read first key/value pair.
            #expect(try stream.next() == .string)
            #expect(try stream.currentString() == "a")
            #expect(try stream.next() == .colon)
            #expect(try stream.next() == .number)
            #expect(try stream.currentNumber().int64 == 1)
            // Now skip the rest of the object.
            #expect(try stream.next() == .comma)
            #expect(try stream.next() == .string)
            #expect(try stream.currentString() == "b")
            #expect(try stream.next() == .colon)
            try stream.skip() // skips "2"
            #expect(try stream.next() == .comma)
            #expect(try stream.next() == .string)
            #expect(try stream.currentString() == "c")
            #expect(try stream.next() == .colon)
            try stream.skip() // skips "3"
            #expect(try stream.next() == .objectEnd)
            #expect(try stream.next() == .comma)
            #expect(try stream.next() == .number)
            #expect(try stream.currentNumber().int64 == 42)
        }
    }

    @Test
    func `skipValue handles nested arrays`() throws {
        let bytes: [UInt8] = Swift.Array(#"[[1,2],[3,[4,5]]],99"#.utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            try stream.skip() // the whole outer array
            #expect(try stream.next() == .comma)
            #expect(try stream.next() == .number)
            #expect(try stream.currentNumber().int64 == 99)
        }
    }

    @Test
    func `skipValue handles escaped quote in string`() throws {
        let bytes: [UInt8] = Swift.Array(#""skip \"this\" too",42"#.utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            try stream.skip()
            #expect(try stream.next() == .comma)
            #expect(try stream.next() == .number)
            #expect(try stream.currentNumber().int64 == 42)
        }
    }

    // MARK: - Depth

    @Test
    func `depth exceeded throws`() throws {
        let bytes: [UInt8] = Swift.Array("[[[[[]]]]]".utf8)
        bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span, limit: 3)
            do {
                _ = try stream.next() // depth 1
                _ = try stream.next() // depth 2
                _ = try stream.next() // depth 3
                _ = try stream.next() // depth 4 — throw
                Issue.record("Expected depthExceeded error")
            } catch let error as RFC_8259.Error {
                if case .depthExceeded(_, let limit) = error {
                    #expect(limit == 3)
                } else {
                    Issue.record("Wrong error: \(error)")
                }
            } catch {
                Issue.record("Wrong error type: \(error)")
            }
        }
    }

    // MARK: - Malformed inputs

    @Test
    func `malformed null throws`() throws {
        let bytes: [UInt8] = Swift.Array("nulX".utf8)
        bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            do {
                _ = try stream.next()
                Issue.record("Expected error")
            } catch let error as RFC_8259.Error {
                if case .unexpectedToken = error {
                    // Pass — we got an unexpectedToken on the byte mismatch.
                } else {
                    Issue.record("Wrong error: \(error)")
                }
            } catch {
                Issue.record("Wrong error type: \(error)")
            }
        }
    }

    @Test
    func `malformed number throws`() throws {
        // Leading zero is forbidden by RFC 8259.
        let bytes: [UInt8] = Swift.Array("007".utf8)
        bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            do {
                _ = try stream.next()
                _ = try stream.currentNumber()
                Issue.record("Expected leadingZeros error")
            } catch let error as RFC_8259.Error {
                if case .invalidNumber(_, let reason) = error, reason == .leadingZeros {
                    // Pass
                } else {
                    Issue.record("Wrong error: \(error)")
                }
            } catch {
                Issue.record("Wrong error type: \(error)")
            }
        }
    }

    @Test
    func `unterminated string throws`() throws {
        let bytes: [UInt8] = Swift.Array(#""unterminated"#.utf8)
        bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            do {
                _ = try stream.next()
                _ = try stream.currentString()
                Issue.record("Expected unterminated error")
            } catch let error as RFC_8259.Error {
                if case .invalidString(_, let reason) = error, reason == .unterminated {
                    // Pass
                } else {
                    Issue.record("Wrong error: \(error)")
                }
            } catch {
                Issue.record("Wrong error type: \(error)")
            }
        }
    }

    @Test
    func `unknown byte throws`() throws {
        let bytes: [UInt8] = Swift.Array("@".utf8)
        bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            do {
                _ = try stream.next()
                Issue.record("Expected unexpectedToken error")
            } catch let error as RFC_8259.Error {
                if case .unexpectedToken(_, let found, _) = error {
                    if case .unknown(let code) = found {
                        #expect(code == ASCII.Code(UInt8(ascii: "@")))
                    } else {
                        Issue.record("Wrong kind: \(found)")
                    }
                } else {
                    Issue.record("Wrong error: \(error)")
                }
            } catch {
                Issue.record("Wrong error type: \(error)")
            }
        }
    }

    // MARK: - Whitespace handling

    @Test
    func `next skips leading whitespace`() throws {
        let bytes: [UInt8] = Swift.Array("   \n\t  null".utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(try stream.next() == .null)
        }
    }

    @Test
    func `next skips whitespace between tokens`() throws {
        let bytes: [UInt8] = Swift.Array(#"{   "key"   :   42   }"#.utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(try stream.next() == .objectStart)
            #expect(try stream.next() == .string)
            #expect(try stream.currentString() == "key")
            #expect(try stream.next() == .colon)
            #expect(try stream.next() == .number)
            #expect(try stream.currentNumber().int64 == 42)
            #expect(try stream.next() == .objectEnd)
        }
    }

    // MARK: - Empty input

    @Test
    func `next on empty input returns nil`() throws {
        let bytes: [UInt8] = []
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(try stream.next() == nil)
        }
    }

    @Test
    func `next on whitespace-only returns nil`() throws {
        let bytes: [UInt8] = Swift.Array("   \n   ".utf8)
        try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            #expect(try stream.next() == nil)
        }
    }

    // MARK: - Token.Kind storage cross-check

    @Test
    func `Token Kind unknown payload variant flows through next`() throws {
        // The .unknown(UInt8) case is reached via the default branch of
        // next()'s byte switch.
        let bytes: [UInt8] = [0xFF]
        bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) in
            let span = buf.span
            var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
            do {
                _ = try stream.next()
                Issue.record("Expected unexpectedToken")
            } catch let error as RFC_8259.Error {
                if case .unexpectedToken(_, let found, _) = error,
                   case .unknown(let byte) = found {
                    #expect(byte == 0xFF)
                } else {
                    Issue.record("Wrong error: \(error)")
                }
            } catch {
                Issue.record("Wrong error type: \(error)")
            }
        }
    }
}
}
