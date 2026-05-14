/// EncoderTests.swift
/// swift-rfc-8259
///
/// Tests for JSON encoding

import Testing
@testable import JSON

extension RFC_8259.Encode {
@Suite("Encoder Tests")
struct Tests {

    // MARK: - Simple Values

    @Test
    func `Encode null`() {
        let value: RFC_8259.Value = nil
        let bytes = value.encode()
        #expect(String(decoding: bytes, as: UTF8.self) == "null")
    }

    @Test
    func `Encode true`() {
        let value: RFC_8259.Value = true
        let bytes = value.encode()
        #expect(String(decoding: bytes, as: UTF8.self) == "true")
    }

    @Test
    func `Encode false`() {
        let value: RFC_8259.Value = false
        let bytes = value.encode()
        #expect(String(decoding: bytes, as: UTF8.self) == "false")
    }

    // MARK: - Numbers

    @Test
    func `Encode integer`() throws {
        let value = try RFC_8259.parse("42")
        let bytes = value.encode()
        #expect(String(decoding: bytes, as: UTF8.self) == "42")
    }

    @Test
    func `Encode negative`() throws {
        let value = try RFC_8259.parse("-123")
        let bytes = value.encode()
        #expect(String(decoding: bytes, as: UTF8.self) == "-123")
    }

    @Test
    func `Encode floating point`() throws {
        let value = try RFC_8259.parse("3.14")
        let bytes = value.encode()
        #expect(String(decoding: bytes, as: UTF8.self) == "3.14")
    }

    @Test
    func `Encode scientific notation preserves original`() throws {
        let value = try RFC_8259.parse("1.5e10")
        let bytes = value.encode()
        #expect(String(decoding: bytes, as: UTF8.self) == "1.5e10")
    }

    // MARK: - Strings

    @Test
    func `Encode simple string`() throws {
        let value: RFC_8259.Value = "hello"
        let bytes = value.encode()
        #expect(String(decoding: bytes, as: UTF8.self) == "\"hello\"")
    }

    @Test
    func `Encode empty string`() {
        let value: RFC_8259.Value = ""
        let bytes = value.encode()
        #expect(String(decoding: bytes, as: UTF8.self) == "\"\"")
    }

    @Test
    func `Encode string with escapes`() {
        let value: RFC_8259.Value = .string("hello\nworld")
        let bytes = value.encode()
        #expect(String(decoding: bytes, as: UTF8.self) == "\"hello\\nworld\"")
    }

    @Test
    func `Encode string with all escape sequences`() {
        let value: RFC_8259.Value = .string("\"\\\u{08}\u{0C}\n\r\t")
        let bytes = value.encode()
        #expect(String(decoding: bytes, as: UTF8.self) == "\"\\\"\\\\\\b\\f\\n\\r\\t\"")
    }

    @Test
    func `Encode string with control character`() {
        let value: RFC_8259.Value = .string("\u{01}")
        let bytes = value.encode()
        #expect(String(decoding: bytes, as: UTF8.self) == "\"\\u0001\"")
    }

    // MARK: - Arrays

    @Test
    func `Encode empty array`() {
        let value: RFC_8259.Value = []
        let bytes = value.encode()
        #expect(String(decoding: bytes, as: UTF8.self) == "[]")
    }

    @Test
    func `Encode array with values`() throws {
        let value = try RFC_8259.parse("[1, 2, 3]")
        let bytes = value.encode()
        #expect(String(decoding: bytes, as: UTF8.self) == "[1,2,3]")
    }

    // MARK: - Objects

    @Test
    func `Encode empty object`() {
        let value: RFC_8259.Value = [:]
        let bytes = value.encode()
        #expect(String(decoding: bytes, as: UTF8.self) == "{}")
    }

    @Test
    func `Encode object`() throws {
        let value: RFC_8259.Value = ["name": "John"]
        let bytes = value.encode()
        #expect(String(decoding: bytes, as: UTF8.self) == "{\"name\":\"John\"}")
    }

    // MARK: - Options

    @Test
    func `Encode with sorted keys`() {
        let value: RFC_8259.Value = ["b": 2, "a": 1]
        let options = RFC_8259.Encode.Options(sortKeys: true)
        let bytes = value.encode(options: options)
        #expect(String(decoding: bytes, as: UTF8.self) == "{\"a\":1,\"b\":2}")
    }

    @Test
    func `Encode with escaped slashes`() {
        let value: RFC_8259.Value = "http://example.com"
        let options = RFC_8259.Encode.Options(escapeSlashes: true)
        let bytes = value.encode(options: options)
        #expect(String(decoding: bytes, as: UTF8.self) == "\"http:\\/\\/example.com\"")
    }

    @Test
    func `Encode pretty printed array`() throws {
        let value = try RFC_8259.parse("[1, 2]")
        let options = RFC_8259.Encode.Options(prettyPrint: true)
        let bytes = value.encode(options: options)
        let expected = """
        [
          1,
          2
        ]
        """
        #expect(String(decoding: bytes, as: UTF8.self) == expected)
    }

    @Test
    func `Encode pretty printed object`() {
        let value: RFC_8259.Value = ["key": "value"]
        let options = RFC_8259.Encode.Options(prettyPrint: true)
        let bytes = value.encode(options: options)
        let expected = """
        {
          "key": "value"
        }
        """
        #expect(String(decoding: bytes, as: UTF8.self) == expected)
    }

    // MARK: - Binary.Serializable

    @Test
    func `Binary.Serializable conformance`() {
        let value: RFC_8259.Value = ["name": "test"]
        let bytes: [UInt8] = value.bytes
        #expect(String(decoding: bytes, as: UTF8.self) == "{\"name\":\"test\"}")
    }

    @Test
    func `Binary.Serializable serialize into buffer`() {
        var buffer: [UInt8] = []
        let value: RFC_8259.Value = 42
        RFC_8259.Value.serialize(value, into: &buffer)
        #expect(String(decoding: buffer, as: UTF8.self) == "42")
    }

    // MARK: - UTF-8 Key Sorting

    @Test
    func `Sort keys by UTF-8 bytes, not Unicode collation`() {
        // "é" is 0xC3 0xA9 in UTF-8, which comes after "e" (0x65) and "f" (0x66)
        // In Unicode collation, "é" might sort near "e", but in UTF-8 byte order
        // it sorts after ASCII characters
        let value: RFC_8259.Value = ["é": 1, "e": 2, "f": 3]
        let options = RFC_8259.Encode.Options(sortKeys: true)
        let bytes = value.encode(options: options)
        let result = String(decoding: bytes, as: UTF8.self)

        // UTF-8 byte order: "e" (0x65) < "f" (0x66) < "é" (0xC3 0xA9)
        #expect(result == "{\"e\":2,\"f\":3,\"é\":1}")
    }

    @Test
    func `Sort keys with emoji by UTF-8 bytes`() {
        // Emoji have high UTF-8 byte values (4-byte sequences starting with 0xF0)
        let value: RFC_8259.Value = ["a": 1, "😀": 2, "z": 3]
        let options = RFC_8259.Encode.Options(sortKeys: true)
        let bytes = value.encode(options: options)
        let result = String(decoding: bytes, as: UTF8.self)

        // UTF-8 byte order: "a" (0x61) < "z" (0x7A) < "😀" (0xF0 0x9F 0x98 0x80)
        #expect(result == "{\"a\":1,\"z\":3,\"😀\":2}")
    }

    // MARK: - Unicode String Encoding

    @Test
    func `Encode string with multi-byte UTF-8`() {
        // Test that encodeScalarUTF8 handles all UTF-8 byte lengths correctly
        let value: RFC_8259.Value = "aéñ中😀"
        let bytes = value.encode()
        let result = String(decoding: bytes, as: UTF8.self)
        #expect(result == "\"aéñ中😀\"")
    }
}
}
