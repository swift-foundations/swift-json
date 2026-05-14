/// RoundTripTests.swift
/// swift-rfc-8259
///
/// Tests for round-trip encode/decode consistency

import Testing
@testable import JSON

extension JSON.Coder {
@Suite("Round-Trip Tests")
struct Tests {

    @Test
    func `Round-trip simple values`() throws {
        for json in ["null", "true", "false"] {
            let value = try JSON.Decode.parse(json)
            let encoded = JSON.Encode.encode(value)
            let reparsed = try JSON.Decode.parse(encoded)
            #expect(value == reparsed)
        }
    }

    @Test
    func `Round-trip integers`() throws {
        for json in ["0", "1", "-1", "42", "-123", "999999999"] {
            let value = try JSON.Decode.parse(json)
            let encoded = JSON.Encode.encode(value)
            let reparsed = try JSON.Decode.parse(encoded)
            #expect(value == reparsed)
        }
    }

    @Test
    func `Round-trip floats`() throws {
        for json in ["0.0", "3.14", "-2.5", "1.5e10", "1e-5"] {
            let value = try JSON.Decode.parse(json)
            let encoded = JSON.Encode.encode(value)
            let reparsed = try JSON.Decode.parse(encoded)
            #expect(value == reparsed)
        }
    }

    @Test
    func `Round-trip strings`() throws {
        for json in ["\"\"", "\"hello\"", "\"hello\\nworld\"", "\"\\u0041\""] {
            let value = try JSON.Decode.parse(json)
            let encoded = JSON.Encode.encode(value)
            let reparsed = try JSON.Decode.parse(encoded)
            #expect(value == reparsed)
        }
    }

    @Test
    func `Round-trip arrays`() throws {
        for json in ["[]", "[1]", "[1, 2, 3]", "[[1], [2]]"] {
            let value = try JSON.Decode.parse(json)
            let encoded = JSON.Encode.encode(value)
            let reparsed = try JSON.Decode.parse(encoded)
            #expect(value == reparsed)
        }
    }

    @Test
    func `Round-trip objects`() throws {
        let json = "{\"name\":\"John\",\"age\":30}"
        let value = try JSON.Decode.parse(json)
        let encoded = JSON.Encode.encode(value)
        let reparsed = try JSON.Decode.parse(encoded)
        #expect(value == reparsed)
    }

    @Test
    func `Round-trip nested structure`() throws {
        let json = "{\"users\":[{\"name\":\"Alice\",\"active\":true}]}"
        let value = try JSON.Decode.parse(json)
        let encoded = JSON.Encode.encode(value)
        let reparsed = try JSON.Decode.parse(encoded)
        #expect(value == reparsed)
    }

    @Test
    func `Round-trip preserves number representation`() throws {
        // Scientific notation should be preserved
        let json = "1.5e10"
        let value = try JSON.Decode.parse(json)
        let encoded = JSON.Encode.encode(value)
        #expect(String(decoding: encoded, as: UTF8.self) == json)
    }

    @Test
    func `Round-trip complex document`() throws {
        let json = """
        {"data":{"items":[{"id":1,"name":"first","tags":["a","b"]},{"id":2,"name":"second","tags":[]}],"count":2,"active":true}}
        """
        let value = try JSON.Decode.parse(json)
        let encoded = JSON.Encode.encode(value)
        let reparsed = try JSON.Decode.parse(encoded)
        #expect(value == reparsed)
    }
}
}
