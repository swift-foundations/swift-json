/// JSONTests.swift
/// swift-json

import Testing
@testable import JSON

@Suite("JSON Tests")
struct JSONTests {

    // MARK: - Literals

    @Test
    func `Null literal`() {
        let json: JSON = nil
        #expect(json.isNull)
    }

    @Test
    func `Boolean literals`() {
        let t: JSON = true
        let f: JSON = false
        #expect(Bool(t) == true)
        #expect(Bool(f) == false)
    }

    @Test
    func `Integer literal`() {
        let json: JSON = 42
        #expect(Int(json) == 42)
    }

    @Test
    func `Float literal`() {
        let json: JSON = 3.14
        #expect(Double(json) == 3.14)
    }

    @Test
    func `String literal`() {
        let json: JSON = "hello"
        #expect(String(json) == "hello")
    }

    @Test
    func `Array literal`() {
        let json: JSON = [1, 2, 3]
        #expect(json.array?.count == 3)
        #expect(Int(json[0]) == 1)
        #expect(Int(json[1]) == 2)
        #expect(Int(json[2]) == 3)
    }

    @Test
    func `Dictionary literal`() {
        let json: JSON = ["name": "John", "age": 30]
        #expect(String(json["name"]) == "John")
        #expect(Int(json["age"]) == 30)
    }

    @Test
    func `Nested literal`() {
        let json: JSON = [
            "user": [
                "name": "John",
                "tags": ["swift", "json"]
            ]
        ]
        #expect(String(json.user.name) == "John")
        #expect(String(json.user.tags[0]) == "swift")
    }

    // MARK: - Dynamic Member Lookup

    @Test
    func `Dynamic member lookup`() {
        let json: JSON = ["name": "John", "age": 30]
        #expect(String(json.name) == "John")
        #expect(Int(json.age) == 30)
    }

    @Test
    func `Missing key returns null`() {
        let json: JSON = ["name": "John"]
        #expect(json.missing.isNull)
    }

    // MARK: - Parsing

    @Test
    func `Parse string`() throws {
        let json = try JSON.parse(#"{"name": "John", "age": 30}"#)
        #expect(String(json.name) == "John")
        #expect(Int(json.age) == 30)
    }

    @Test
    func `Parse array`() throws {
        let json = try JSON.parse("[1, 2, 3]")
        #expect(Int(json[0]) == 1)
        #expect(Int(json[1]) == 2)
        #expect(Int(json[2]) == 3)
    }

    // MARK: - Serialization

    @Test
    func `Serialize to string`() {
        let json: JSON = ["name": "John"]
        let string = json.serialize()
        #expect(string.contains("name"))
        #expect(string.contains("John"))
    }

    @Test
    func `Round-trip`() throws {
        let original: JSON = [
            "name": "John",
            "age": 30,
            "verified": true,
            "tags": ["swift", "json"]
        ]
        let string = original.serialize()
        let parsed = try JSON.parse(string)
        #expect(String(parsed.name) == "John")
        #expect(Int(parsed.age) == 30)
        #expect(Bool(parsed.verified) == true)
        #expect(String(parsed.tags[0]) == "swift")
    }

    // MARK: - JSON.Serializable

    @Test
    func `String serializable`() throws {
        let string = "hello"
        let json = string.json
        #expect(String(json) == "hello")

        let decoded = try String(json: json)
        #expect(decoded == "hello")
    }

    @Test
    func `Int serializable`() throws {
        let num = 42
        let json = num.json
        #expect(Int(json) == 42)

        let decoded = try Int(json: json)
        #expect(decoded == 42)
    }

    @Test
    func `Array serializable`() throws {
        let arr = [1, 2, 3]
        let json = arr.json
        #expect(Int(json[0]) == 1)

        let decoded = try [Int](json: json)
        #expect(decoded == [1, 2, 3])
    }

    @Test
    func `Dictionary serializable`() throws {
        let dict = ["a": 1, "b": 2]
        let json = dict.json
        #expect(Int(json["a"]) == 1)

        let decoded = try [String: Int](json: json)
        #expect(decoded["a"] == 1)
        #expect(decoded["b"] == 2)
    }

    @Test
    func `Optional serializable`() throws {
        let some: Int? = 42
        let none: Int? = nil

        #expect(Int(some.json) == 42)
        #expect(none.json.isNull)

        let decodedSome = try Int?(json: JSON(42))
        let decodedNone = try Int?(json: .null)
        #expect(decodedSome == 42)
        #expect(decodedNone == nil)
    }
}
