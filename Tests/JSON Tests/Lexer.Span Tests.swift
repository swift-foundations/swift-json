/// Lexer.Span Tests.swift
/// swift-rfc-8259
///
/// Tests for the wholesale parser introduced in Phase A1 of
/// `parse-performance-architecture.md`. The internal parser lives at
/// `RFC_8259.Decode.Implementation` (backed by `Lexer.Scanner` from
/// swift-lexer-primitives); the public entry points (`RFC_8259.decode`,
/// `RFC_8259.parse`) dispatch to it for contiguous-bytes inputs.

import Testing
@testable import JSON

extension RFC_8259.Decode {
@Suite("Lexer.Span Tests")
struct Tests {

    // MARK: - Structural tokens via Span

    @Test
    func `Span parses structural tokens via [UInt8] path`() throws {
        let bytes: [UInt8] = Swift.Array("[{},[]]".utf8)
        let value = try RFC_8259.decode(bytes)
        // Outer array has one object and one array.
        #expect(value.array?.count == 2)
        #expect(value[0]?.object?.count == 0)
        #expect(value[1]?.array?.count == 0)
    }

    @Test
    func `Span parses structural tokens via String path`() throws {
        let value = try RFC_8259.decode("[{},[]]")
        #expect(value.array?.count == 2)
        #expect(value[0]?.object?.count == 0)
        #expect(value[1]?.array?.count == 0)
    }

    // MARK: - Literals

    @Test
    func `Span parses null`() throws {
        let value = try RFC_8259.decode("null")
        #expect(value.isNull)
    }

    @Test
    func `Span parses true`() throws {
        let value = try RFC_8259.decode("true")
        #expect(value.bool == true)
    }

    @Test
    func `Span parses false`() throws {
        let value = try RFC_8259.decode("false")
        #expect(value.bool == false)
    }

    // MARK: - Numbers

    @Test
    func `Span parses integer`() throws {
        let value = try RFC_8259.decode("42")
        #expect(value.number?.int64 == 42)
    }

    @Test
    func `Span parses negative integer`() throws {
        let value = try RFC_8259.decode("-123")
        #expect(value.number?.int64 == -123)
    }

    @Test
    func `Span parses zero`() throws {
        let value = try RFC_8259.decode("0")
        #expect(value.number?.int64 == 0)
    }

    @Test
    func `Span parses negative zero`() throws {
        let value = try RFC_8259.decode("-0")
        #expect(value.number?.double == 0)
    }

    @Test
    func `Span parses floating point`() throws {
        let value = try RFC_8259.decode("3.14")
        #expect(value.number?.double == 3.14)
    }

    @Test
    func `Span parses scientific notation`() throws {
        let value = try RFC_8259.decode("1.5e10")
        #expect(value.number?.double == 1.5e10)
    }

    @Test
    func `Span parses uppercase exponent`() throws {
        let value = try RFC_8259.decode("1E10")
        #expect(value.number?.double == 1e10)
    }

    @Test
    func `Span rejects leading zero`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode("007")
        }
    }

    @Test
    func `Span rejects 1e999 overflow`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode("1e999")
        }
    }

    @Test
    func `Span rejects bare decimal point`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode(".5")
        }
    }

    @Test
    func `Span rejects trailing decimal point`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode("5.")
        }
    }

    // MARK: - Strings

    @Test
    func `Span parses simple string`() throws {
        let value = try RFC_8259.decode("\"hello\"")
        #expect(value.string == "hello")
    }

    @Test
    func `Span parses empty string`() throws {
        let value = try RFC_8259.decode("\"\"")
        #expect(value.string == "")
    }

    @Test
    func `Span parses string with escapes`() throws {
        let value = try RFC_8259.decode("\"hello\\nworld\"")
        #expect(value.string == "hello\nworld")
    }

    @Test
    func `Span parses all escape sequences`() throws {
        let value = try RFC_8259.decode("\"\\\"\\\\\\b\\f\\n\\r\\t\"")
        #expect(value.string == "\"\\\u{08}\u{0C}\n\r\t")
    }

    @Test
    func `Span parses solidus escape`() throws {
        let value = try RFC_8259.decode("\"\\/\"")
        #expect(value.string == "/")
    }

    @Test
    func `Span parses BMP unicode escape`() throws {
        let value = try RFC_8259.decode("\"\\u0041\"")
        #expect(value.string == "A")
    }

    @Test
    func `Span parses surrogate pair via unicode escapes`() throws {
        // U+1F600 (😀) = 😀
        let value = try RFC_8259.decode("\"\\uD83D\\uDE00\"")
        #expect(value.string == "😀")
    }

    @Test
    func `Span parses UTF-8 multi-byte sequence (Cyrillic)`() throws {
        let value = try RFC_8259.decode("\"Привет\"")
        #expect(value.string == "Привет")
    }

    @Test
    func `Span parses UTF-8 multi-byte sequence (CJK)`() throws {
        let value = try RFC_8259.decode("\"日本語\"")
        #expect(value.string == "日本語")
    }

    @Test
    func `Span parses UTF-8 4-byte emoji directly`() throws {
        let value = try RFC_8259.decode("\"🚀\"")
        #expect(value.string == "🚀")
    }

    @Test
    func `Span rejects unterminated string`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode("\"hello")
        }
    }

    @Test
    func `Span rejects invalid escape`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode("\"\\q\"")
        }
    }

    @Test
    func `Span rejects incomplete unicode escape`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode("\"\\u00\"")
        }
    }

    @Test
    func `Span rejects invalid hex in unicode escape`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode("\"\\uGGGG\"")
        }
    }

    @Test
    func `Span rejects high surrogate without low`() throws {
        // \uD83D is a high surrogate, but no low surrogate follows.
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode("\"\\uD83D\"")
        }
    }

    @Test
    func `Span rejects unescaped control character`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode("\"\u{01}\"")
        }
    }

    @Test
    func `Span rejects unescaped newline in string`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode("\"hello\nworld\"")
        }
    }

    // MARK: - Arrays

    @Test
    func `Span parses empty array`() throws {
        let value = try RFC_8259.decode("[]")
        #expect(value.array?.count == 0)
    }

    @Test
    func `Span parses array with values`() throws {
        let value = try RFC_8259.decode("[1, 2, 3]")
        #expect(value.array?.count == 3)
        #expect(value[0]?.number?.int64 == 1)
        #expect(value[1]?.number?.int64 == 2)
        #expect(value[2]?.number?.int64 == 3)
    }

    @Test
    func `Span parses array with mixed types`() throws {
        let value = try RFC_8259.decode("[1, \"two\", true, null]")
        #expect(value[0]?.number?.int64 == 1)
        #expect(value[1]?.string == "two")
        #expect(value[2]?.bool == true)
        #expect(value[3]?.isNull == true)
    }

    @Test
    func `Span rejects trailing comma in array`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode("[1, 2, ]")
        }
    }

    @Test
    func `Span rejects unclosed array`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode("[1, 2")
        }
    }

    // MARK: - Objects

    @Test
    func `Span parses empty object`() throws {
        let value = try RFC_8259.decode("{}")
        #expect(value.object?.count == 0)
    }

    @Test
    func `Span parses object with members`() throws {
        let value = try RFC_8259.decode("{\"name\": \"John\", \"age\": 30}")
        #expect(value["name"]?.string == "John")
        #expect(value["age"]?.number?.int64 == 30)
    }

    @Test
    func `Span preserves object insertion order`() throws {
        let json = "{\"z\":1,\"a\":2,\"m\":3}"
        let value = try RFC_8259.decode(json)
        let keys = value.object?.map(\.key)
        #expect(keys == ["z", "a", "m"])
    }

    @Test
    func `Span rejects unclosed object`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode("{\"key\": 1")
        }
    }

    @Test
    func `Span rejects missing colon`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode("{\"key\" 1}")
        }
    }

    @Test
    func `Span rejects unquoted object key`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode("{key: 1}")
        }
    }

    // MARK: - Nested structures

    @Test
    func `Span parses nested structure`() throws {
        let json = """
        {
            "users": [
                {"name": "Alice", "active": true},
                {"name": "Bob", "active": false}
            ]
        }
        """
        let value = try RFC_8259.decode(json)
        #expect(value["users"]?[0]?["name"]?.string == "Alice")
        #expect(value["users"]?[0]?["active"]?.bool == true)
        #expect(value["users"]?[1]?["name"]?.string == "Bob")
        #expect(value["users"]?[1]?["active"]?.bool == false)
    }

    // MARK: - Depth limit

    @Test
    func `Span respects depth limit`() throws {
        let json = String(repeating: "[", count: 10) + "1" + String(repeating: "]", count: 10)
        let value = try RFC_8259.decode(json)
        #expect(value.array != nil)
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode(json, maxDepth: 5)
        }
    }

    // MARK: - Whitespace and trailing content

    @Test
    func `Span handles all whitespace types between tokens`() throws {
        let json = "[\t\n\r 1\t\n\r ,\t\n\r 2\t\n\r ]"
        let value = try RFC_8259.decode(json)
        #expect(value[0]?.number?.int64 == 1)
        #expect(value[1]?.number?.int64 == 2)
    }

    @Test
    func `Span rejects trailing content`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode("123 456")
        }
    }

    @Test
    func `Span rejects multiple top-level values`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode("{}{}")
        }
    }

    @Test
    func `Span rejects empty input`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode("")
        }
    }

    @Test
    func `Span rejects whitespace-only input`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.decode("   ")
        }
    }

    // MARK: - Lazy position tracking

    @Test
    func `Span lazy position computes line/column on error`() throws {
        // Input has the error on line 3, column 1 (the unterminated string).
        let json = "{\n  \"good\": 1,\n  \"bad\""  // missing colon + value + brace
        do {
            _ = try RFC_8259.decode(json)
            Issue.record("Expected parse error")
        } catch let err as RFC_8259.Error {
            // We don't care which exact error fires; just that the
            // position is at a sensible line.
            let offset: Int
            switch err {
            case .unexpectedToken(let pos, _, _): offset = Int(bitPattern: pos.offset)
            case .unexpectedEndOfInput(let pos, _): offset = Int(bitPattern: pos.offset)
            case .invalidNumber(let pos, _): offset = Int(bitPattern: pos.offset)
            case .invalidString(let pos, _): offset = Int(bitPattern: pos.offset)
            case .invalidUTF8(let pos, _): offset = Int(bitPattern: pos.offset)
            case .depthExceeded(let pos, _): offset = Int(bitPattern: pos.offset)
            case .trailingContent(let pos): offset = Int(bitPattern: pos.offset)
            }
            // Offset should be > 0 and within input bounds.
            #expect(offset > 0)
            #expect(offset <= json.utf8.count)
        }
    }

    @Test
    func `Span lazy position reports line 2 after a newline`() throws {
        // After the migration to Lexer.Scanner, line:column tracking is
        // O(1) via Text.Location.Tracker (updated incrementally by the
        // parser's skipWhitespace). The original cache-invariant
        // mechanism (cachedPosition / cachedPositionOffset / per-error
        // rescan) is gone. This test verifies the equivalent observable
        // behaviour: a syntax error AFTER a newline reports line 2.
        //
        // Input: `{\n  "bad"` — unterminated key string on line 2.
        let json = "{\n  \"bad"
        do {
            _ = try RFC_8259.decode(json)
            Issue.record("Expected parse error")
        } catch let err as RFC_8259.Error {
            let location: Text.Location
            switch err {
            case .unexpectedToken(let pos, _, _): location = pos.location
            case .unexpectedEndOfInput(let pos, _): location = pos.location
            case .invalidNumber(let pos, _): location = pos.location
            case .invalidString(let pos, _): location = pos.location
            case .invalidUTF8(let pos, _): location = pos.location
            case .depthExceeded(let pos, _): location = pos.location
            case .trailingContent(let pos): location = pos.location
            }
            #expect(location.line.underlying == 2)
        }
    }
}
}
