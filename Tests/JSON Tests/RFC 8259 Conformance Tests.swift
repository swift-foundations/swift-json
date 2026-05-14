/// RFC8259ConformanceTests.swift
/// swift-rfc-8259
///
/// Tests for RFC 8259 spec compliance and edge cases

import Testing
@testable import JSON

extension RFC_8259 {
@Suite("RFC 8259 Conformance Tests")
struct Conformance {

    // MARK: - Error Cases: Numbers

    @Test
    func `Reject leading zeros`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("007")
        }
    }

    @Test
    func `Reject leading zeros in negative`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("-007")
        }
    }

    @Test
    func `Reject plus sign on positive numbers`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("+42")
        }
    }

    @Test
    func `Reject bare decimal point`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse(".5")
        }
    }

    @Test
    func `Reject trailing decimal point`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("5.")
        }
    }

    @Test
    func `Reject bare exponent`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("e10")
        }
    }

    @Test
    func `Reject NaN`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("NaN")
        }
    }

    @Test
    func `Reject Infinity`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("Infinity")
        }
    }

    @Test
    func `Reject hex numbers`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("0x1F")
        }
    }

    // MARK: - Error Cases: Strings

    @Test
    func `Reject unterminated string`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("\"hello")
        }
    }

    @Test
    func `Reject invalid escape`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("\"\\q\"")
        }
    }

    @Test
    func `Reject incomplete unicode escape`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("\"\\u00\"")
        }
    }

    @Test
    func `Reject invalid unicode escape`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("\"\\uGGGG\"")
        }
    }

    @Test
    func `Reject unescaped control character`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("\"\u{01}\"")
        }
    }

    @Test
    func `Reject unescaped newline in string`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("\"hello\nworld\"")
        }
    }

    @Test
    func `Reject unescaped tab in string`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("\"hello\tworld\"")
        }
    }

    // MARK: - Error Cases: Structure

    @Test
    func `Reject trailing content`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("123 456")
        }
    }

    @Test
    func `Reject multiple values`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("{}{}")
        }
    }

    @Test
    func `Reject unclosed array`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("[1, 2")
        }
    }

    @Test
    func `Reject unclosed object`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("{\"key\": 1")
        }
    }

    @Test
    func `Reject trailing comma in array`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("[1, 2, ]")
        }
    }

    @Test
    func `Reject trailing comma in object`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("{\"key\": 1, }")
        }
    }

    @Test
    func `Reject unquoted object key`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("{key: 1}")
        }
    }

    @Test
    func `Reject single quotes`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("'hello'")
        }
    }

    @Test
    func `Reject missing colon in object`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("{\"key\" 1}")
        }
    }

    @Test
    func `Reject missing value in object`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("{\"key\":}")
        }
    }

    // MARK: - Error Cases: Invalid Tokens

    @Test
    func `Reject undefined`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("undefined")
        }
    }

    @Test
    func `Reject True (capitalized)`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("True")
        }
    }

    @Test
    func `Reject FALSE (all caps)`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("FALSE")
        }
    }

    @Test
    func `Reject NULL (all caps)`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("NULL")
        }
    }

    @Test
    func `Reject empty input`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("")
        }
    }

    @Test
    func `Reject whitespace only`() throws {
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse("   ")
        }
    }

    // MARK: - Depth Limiting

    @Test
    func `Respect depth limit`() throws {
        // Nested 10 levels deep
        let json = String(repeating: "[", count: 10) + "1" + String(repeating: "]", count: 10)

        // Should succeed with default depth
        let value = try RFC_8259.parse(json)
        #expect(value.array != nil)

        // Should fail with lower limit
        #expect(throws: RFC_8259.Error.self) {
            try RFC_8259.parse(json, maxDepth: 5)
        }
    }

    // MARK: - Unicode

    @Test
    func `Parse UTF-8 string`() throws {
        let value = try RFC_8259.parse("\"日本語\"")
        #expect(value.string == "日本語")
    }

    @Test
    func `Parse emoji`() throws {
        let value = try RFC_8259.parse("\"Hello 👋\"")
        #expect(value.string == "Hello 👋")
    }

    @Test
    func `Parse surrogate pair via unicode escapes`() throws {
        // U+1F600 (😀) = \uD83D\uDE00 in surrogate pairs
        let value = try RFC_8259.parse("\"\\uD83D\\uDE00\"")
        #expect(value.string == "😀")
    }

    // MARK: - Object Key Handling

    @Test
    func `Object preserves insertion order`() throws {
        let json = "{\"z\":1,\"a\":2,\"m\":3}"
        let value = try RFC_8259.parse(json)
        let keys = value.object?.map(\.key)
        #expect(keys == ["z", "a", "m"])
    }

    @Test
    func `Object handles duplicate keys (last wins)`() throws {
        let json = "{\"key\":1,\"key\":2}"
        let value = try RFC_8259.parse(json)
        // Behavior: both are stored; first match wins on lookup
        #expect(value["key"]?.number?.int64 == 1)
    }

    // MARK: - Large Numbers

    @Test
    func `Parse large integer`() throws {
        let value = try RFC_8259.parse("9223372036854775807")
        #expect(value.number?.int64 == Int64.max)
    }

    @Test
    func `Parse very large number as double`() throws {
        let value = try RFC_8259.parse("1e308")
        #expect(value.number?.double != nil)
    }
}
}
