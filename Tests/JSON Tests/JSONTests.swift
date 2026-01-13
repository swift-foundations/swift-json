/// JSONTests.swift
/// swift-json

import Testing
@testable import JSON

@Suite("JSON Tests")
struct JSONTests {

    // MARK: - Literals

    @Test("Null literal")
    func nullLiteral() {
        let json: JSON = nil
        #expect(json.isNull)
    }

    @Test("Boolean literals")
    func booleanLiterals() {
        let t: JSON = true
        let f: JSON = false
        #expect(t.bool == true)
        #expect(f.bool == false)
    }

    @Test("Integer literal")
    func integerLiteral() {
        let json: JSON = 42
        #expect(json.int == 42)
    }

    @Test("Float literal")
    func floatLiteral() {
        let json: JSON = 3.14
        #expect(json.double == 3.14)
    }

    @Test("String literal")
    func stringLiteral() {
        let json: JSON = "hello"
        #expect(json.string == "hello")
    }

    @Test("Array literal")
    func arrayLiteral() {
        let json: JSON = [1, 2, 3]
        #expect(json.array?.count == 3)
        #expect(json[0].int == 1)
        #expect(json[1].int == 2)
        #expect(json[2].int == 3)
    }

    @Test("Dictionary literal")
    func dictionaryLiteral() {
        let json: JSON = ["name": "John", "age": 30]
        #expect(json["name"].string == "John")
        #expect(json["age"].int == 30)
    }

    @Test("Nested literal")
    func nestedLiteral() {
        let json: JSON = [
            "user": [
                "name": "John",
                "tags": ["swift", "json"]
            ]
        ]
        #expect(json.user.name.string == "John")
        #expect(json.user.tags[0].string == "swift")
    }

    // MARK: - Dynamic Member Lookup

    @Test("Dynamic member lookup")
    func dynamicMemberLookup() {
        let json: JSON = ["name": "John", "age": 30]
        #expect(json.name.string == "John")
        #expect(json.age.int == 30)
    }

    @Test("Missing key returns null")
    func missingKeyReturnsNull() {
        let json: JSON = ["name": "John"]
        #expect(json.missing.isNull)
    }

    // MARK: - Parsing

    @Test("Parse string")
    func parseString() throws {
        let json = try JSON.parse(#"{"name": "John", "age": 30}"#)
        #expect(json.name.string == "John")
        #expect(json.age.int == 30)
    }

    @Test("Parse array")
    func parseArray() throws {
        let json = try JSON.parse("[1, 2, 3]")
        #expect(json[0].int == 1)
        #expect(json[1].int == 2)
        #expect(json[2].int == 3)
    }

    // MARK: - Serialization

    @Test("Serialize to string")
    func serializeToString() {
        let json: JSON = ["name": "John"]
        let string = json.serialize()
        #expect(string.contains("name"))
        #expect(string.contains("John"))
    }

    @Test("Round-trip")
    func roundTrip() throws {
        let original: JSON = [
            "name": "John",
            "age": 30,
            "verified": true,
            "tags": ["swift", "json"]
        ]
        let string = original.serialize()
        let parsed = try JSON.parse(string)
        #expect(parsed.name.string == "John")
        #expect(parsed.age.int == 30)
        #expect(parsed.verified.bool == true)
        #expect(parsed.tags[0].string == "swift")
    }

    // MARK: - JSON.Serializable

    @Test("String serializable")
    func stringSerializable() throws {
        let string = "hello"
        let json = string.json
        #expect(json.string == "hello")

        let decoded = try String(json: json)
        #expect(decoded == "hello")
    }

    @Test("Int serializable")
    func intSerializable() throws {
        let num = 42
        let json = num.json
        #expect(json.int == 42)

        let decoded = try Int(json: json)
        #expect(decoded == 42)
    }

    @Test("Array serializable")
    func arraySerializable() throws {
        let arr = [1, 2, 3]
        let json = arr.json
        #expect(json[0].int == 1)

        let decoded = try [Int](json: json)
        #expect(decoded == [1, 2, 3])
    }

    @Test("Dictionary serializable")
    func dictionarySerializable() throws {
        let dict = ["a": 1, "b": 2]
        let json = dict.json
        #expect(json["a"].int == 1)

        let decoded = try [String: Int](json: json)
        #expect(decoded["a"] == 1)
        #expect(decoded["b"] == 2)
    }

    @Test("Optional serializable")
    func optionalSerializable() throws {
        let some: Int? = 42
        let none: Int? = nil

        #expect(some.json.int == 42)
        #expect(none.json.isNull)

        let decodedSome = try Int?(json: JSON(42))
        let decodedNone = try Int?(json: .null)
        #expect(decodedSome == 42)
        #expect(decodedNone == nil)
    }
}
