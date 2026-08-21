import Testing

@testable import JSON

extension JSON.Encode {
    @Suite
    struct Test {

        @Test
        func `Encode null`() {
            let value: RFC_8259.Value = nil
            let bytes = JSON.Encode.encode(value)
            #expect(String(decoding: bytes, as: UTF8.self) == "null")
        }

        @Test
        func `Encode true`() {
            let value: RFC_8259.Value = true
            let bytes = JSON.Encode.encode(value)
            #expect(String(decoding: bytes, as: UTF8.self) == "true")
        }

        @Test
        func `Encode false`() {
            let value: RFC_8259.Value = false
            let bytes = JSON.Encode.encode(value)
            #expect(String(decoding: bytes, as: UTF8.self) == "false")
        }

        @Test
        func `Encode integer`() throws {
            let value = try JSON.Decode.parse("42")
            let bytes = JSON.Encode.encode(value)
            #expect(String(decoding: bytes, as: UTF8.self) == "42")
        }

        @Test
        func `Encode negative`() throws {
            let value = try JSON.Decode.parse("-123")
            let bytes = JSON.Encode.encode(value)
            #expect(String(decoding: bytes, as: UTF8.self) == "-123")
        }

        @Test
        func `Encode floating point`() throws {
            let value = try JSON.Decode.parse("3.14")
            let bytes = JSON.Encode.encode(value)
            #expect(String(decoding: bytes, as: UTF8.self) == "3.14")
        }

        @Test
        func `Encode scientific notation preserves original`() throws {
            let value = try JSON.Decode.parse("1.5e10")
            let bytes = JSON.Encode.encode(value)
            #expect(String(decoding: bytes, as: UTF8.self) == "1.5e10")
        }

        @Test
        func `Encode simple string`() throws {
            let value: RFC_8259.Value = "hello"
            let bytes = JSON.Encode.encode(value)
            #expect(String(decoding: bytes, as: UTF8.self) == "\"hello\"")
        }

        @Test
        func `Encode empty string`() {
            let value: RFC_8259.Value = ""
            let bytes = JSON.Encode.encode(value)
            #expect(String(decoding: bytes, as: UTF8.self) == "\"\"")
        }

        @Test
        func `Encode string with escapes`() {
            let value: RFC_8259.Value = .string("hello\nworld")
            let bytes = JSON.Encode.encode(value)
            #expect(String(decoding: bytes, as: UTF8.self) == "\"hello\\nworld\"")
        }

        @Test
        func `Encode string with all escape sequences`() {
            let value: RFC_8259.Value = .string("\"\\\u{08}\u{0C}\n\r\t")
            let bytes = JSON.Encode.encode(value)
            #expect(String(decoding: bytes, as: UTF8.self) == "\"\\\"\\\\\\b\\f\\n\\r\\t\"")
        }

        @Test
        func `Encode string with control character`() {
            let value: RFC_8259.Value = .string("\u{01}")
            let bytes = JSON.Encode.encode(value)
            #expect(String(decoding: bytes, as: UTF8.self) == "\"\\u0001\"")
        }

        @Test
        func `Encode empty array`() {
            let value: RFC_8259.Value = []
            let bytes = JSON.Encode.encode(value)
            #expect(String(decoding: bytes, as: UTF8.self) == "[]")
        }

        @Test
        func `Encode array with values`() throws {
            let value = try JSON.Decode.parse("[1, 2, 3]")
            let bytes = JSON.Encode.encode(value)
            #expect(String(decoding: bytes, as: UTF8.self) == "[1,2,3]")
        }

        @Test
        func `Encode empty object`() {
            let value: RFC_8259.Value = [:]
            let bytes = JSON.Encode.encode(value)
            #expect(String(decoding: bytes, as: UTF8.self) == "{}")
        }

        @Test
        func `Encode object`() throws {
            let value: RFC_8259.Value = ["name": "John"]
            let bytes = JSON.Encode.encode(value)
            #expect(String(decoding: bytes, as: UTF8.self) == "{\"name\":\"John\"}")
        }

        @Test
        func `Encode with sorted keys`() {
            let value: RFC_8259.Value = ["b": 2, "a": 1]
            let options = JSON.Encode.Options(sortKeys: true)
            let bytes = JSON.Encode.encode(value, options: options)
            #expect(String(decoding: bytes, as: UTF8.self) == "{\"a\":1,\"b\":2}")
        }

        @Test
        func `Encode with escaped slashes`() {
            let value: RFC_8259.Value = "http://example.com"
            let options = JSON.Encode.Options(escapeSlashes: true)
            let bytes = JSON.Encode.encode(value, options: options)
            #expect(String(decoding: bytes, as: UTF8.self) == "\"http:\\/\\/example.com\"")
        }

        @Test
        func `Encode pretty printed array`() throws {
            let value = try JSON.Decode.parse("[1, 2]")
            let options = JSON.Encode.Options(prettyPrint: true)
            let bytes = JSON.Encode.encode(value, options: options)
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
            let options = JSON.Encode.Options(prettyPrint: true)
            let bytes = JSON.Encode.encode(value, options: options)
            let expected = """
                {
                  "key": "value"
                }
                """
            #expect(String(decoding: bytes, as: UTF8.self) == expected)
        }

        @Test
        func `JSON.Encode.encode returns bytes`() {
            let value: RFC_8259.Value = ["name": "test"]
            let bytes = JSON.Encode.encode(value)
            #expect(String(decoding: bytes, as: UTF8.self) == "{\"name\":\"test\"}")
        }

        @Test
        func `JSON.Encode.encode appends into buffer`() {
            var buffer: [UInt8] = []
            let value: RFC_8259.Value = 42
            JSON.Encode.encode(value, into: &buffer)
            #expect(String(decoding: buffer, as: UTF8.self) == "42")
        }

        @Test
        func `Sort keys by UTF-8 bytes, not Unicode collation`() {

            let value: RFC_8259.Value = ["é": 1, "e": 2, "f": 3]
            let options = JSON.Encode.Options(sortKeys: true)
            let bytes = JSON.Encode.encode(value, options: options)
            let result = String(decoding: bytes, as: UTF8.self)

            #expect(result == "{\"e\":2,\"f\":3,\"é\":1}")
        }

        @Test
        func `Sort keys with emoji by UTF-8 bytes`() {

            let value: RFC_8259.Value = ["a": 1, "😀": 2, "z": 3]
            let options = JSON.Encode.Options(sortKeys: true)
            let bytes = JSON.Encode.encode(value, options: options)
            let result = String(decoding: bytes, as: UTF8.self)

            #expect(result == "{\"a\":1,\"z\":3,\"😀\":2}")
        }

        @Test
        func `Encode string with multi-byte UTF-8`() {

            let value: RFC_8259.Value = "aéñ中😀"
            let bytes = JSON.Encode.encode(value)
            let result = String(decoding: bytes, as: UTF8.self)
            #expect(result == "\"aéñ中😀\"")
        }
    }
}
