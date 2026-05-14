/// Serializable.EventStream Tests.swift
/// swift-json
///
/// Tests for `JSON.Serializable.deserialize(events:)` and
/// `JSON.Serializable.from(eventDecodingJsonBytes:)` introduced by
/// Phase A1 of the streaming-deserialize arc.
///
/// Coverage:
/// - Foundational conformers (String, Int, Int64, Double, Bool,
///   Optional, Array, Dictionary, JSON) round-trip correctly via the
///   event-grain path.
/// - The §4.3 default-fallback short-circuit is exercised — a
///   non-overriding conformer's `deserialize(events:)` produces the
///   same output as the existing tree path.
/// - `from(eventDecodingJsonBytes:)` dispatches correctly on
///   contiguous storage (`[UInt8]`, `String.UTF8View`).

import Testing
@testable import JSON

@Suite("Serializable EventStream Tests")
struct SerializableEventStreamTests {

    // MARK: - Foundational conformers via event-grain

    @Test
    func `String round-trips via from eventDecodingJsonBytes`() throws {
        let bytes: [UInt8] = Swift.Array(#""hello world""#.utf8)
        let result = try String.from(eventDecodingJsonBytes: bytes)
        #expect(result == "hello world")
    }

    @Test
    func `Int round-trips via from eventDecodingJsonBytes`() throws {
        let bytes: [UInt8] = Swift.Array("42".utf8)
        let result = try Int.from(eventDecodingJsonBytes: bytes)
        #expect(result == 42)
    }

    @Test
    func `Int64 round-trips via from eventDecodingJsonBytes`() throws {
        let bytes: [UInt8] = Swift.Array("9223372036854775807".utf8)
        let result = try Int64.from(eventDecodingJsonBytes: bytes)
        #expect(result == 9223372036854775807)
    }

    @Test
    func `Double round-trips via from eventDecodingJsonBytes`() throws {
        let bytes: [UInt8] = Swift.Array("3.14159".utf8)
        let result = try Double.from(eventDecodingJsonBytes: bytes)
        #expect(result == 3.14159)
    }

    @Test
    func `Bool true round-trips via event-grain`() throws {
        let bytes: [UInt8] = Swift.Array("true".utf8)
        let result = try Bool.from(eventDecodingJsonBytes: bytes)
        #expect(result == true)
    }

    @Test
    func `Bool false round-trips via event-grain`() throws {
        let bytes: [UInt8] = Swift.Array("false".utf8)
        let result = try Bool.from(eventDecodingJsonBytes: bytes)
        #expect(result == false)
    }

    @Test
    func `Optional nil round-trips via event-grain`() throws {
        let bytes: [UInt8] = Swift.Array("null".utf8)
        let result: Int? = try Int?.from(eventDecodingJsonBytes: bytes)
        #expect(result == nil)
    }

    @Test
    func `Optional value round-trips via event-grain`() throws {
        let bytes: [UInt8] = Swift.Array("42".utf8)
        let result: Int? = try Int?.from(eventDecodingJsonBytes: bytes)
        #expect(result == 42)
    }

    @Test
    func `Array of Int round-trips via event-grain`() throws {
        let bytes: [UInt8] = Swift.Array("[1,2,3,4,5]".utf8)
        let result: [Int] = try [Int].from(eventDecodingJsonBytes: bytes)
        #expect(result == [1, 2, 3, 4, 5])
    }

    @Test
    func `Empty array round-trips via event-grain`() throws {
        let bytes: [UInt8] = Swift.Array("[]".utf8)
        let result: [Int] = try [Int].from(eventDecodingJsonBytes: bytes)
        #expect(result.isEmpty)
    }

    @Test
    func `Array of String round-trips via event-grain`() throws {
        let bytes: [UInt8] = Swift.Array(#"["a","b","c"]"#.utf8)
        let result: [String] = try [String].from(eventDecodingJsonBytes: bytes)
        #expect(result == ["a", "b", "c"])
    }

    @Test
    func `Dictionary of String Int round-trips via event-grain`() throws {
        let bytes: [UInt8] = Swift.Array(#"{"a":1,"b":2,"c":3}"#.utf8)
        let result: [String: Int] = try [String: Int].from(eventDecodingJsonBytes: bytes)
        #expect(result["a"] == 1)
        #expect(result["b"] == 2)
        #expect(result["c"] == 3)
        #expect(result.count == 3)
    }

    @Test
    func `Empty dictionary round-trips via event-grain`() throws {
        let bytes: [UInt8] = Swift.Array("{}".utf8)
        let result: [String: Int] = try [String: Int].from(eventDecodingJsonBytes: bytes)
        #expect(result.isEmpty)
    }

    @Test
    func `Nested Array of Array round-trips via event-grain`() throws {
        let bytes: [UInt8] = Swift.Array("[[1,2],[3,4],[5,6]]".utf8)
        let result: [[Int]] = try [[Int]].from(eventDecodingJsonBytes: bytes)
        #expect(result == [[1, 2], [3, 4], [5, 6]])
    }

    @Test
    func `JSON itself round-trips via event-grain`() throws {
        let bytes: [UInt8] = Swift.Array(#"{"key":"value","number":42}"#.utf8)
        let result = try JSON.from(eventDecodingJsonBytes: bytes)
        #expect(String(result["key"]) == "value")
        #expect(Int(result["number"]) == 42)
    }

    // MARK: - §4.3 default-fallback non-regression (correctness)

    // FooDefault inherits the protocol-extension default
    // deserialize(events:) which goes through JSON.Assemble.from(_:).
    // This validates the fallback path produces the same result as
    // the existing tree-grain init(jsonBytes:).

    struct FooDefault: JSON.Serializable {
        let name: String
        let age: Int

        static func serialize(_ value: FooDefault) -> JSON {
            ["name": .string(value.name), "age": .number(value.age)]
        }

        static func deserialize(_ json: JSON) throws(JSON.Error) -> FooDefault {
            let name = String(json.name)
            guard !name.isEmpty else {
                throw .missingKey("name")
            }
            guard let age = Int(json.age) else {
                throw .missingKey("age")
            }
            return FooDefault(name: name, age: age)
        }

        // Deliberately does NOT override deserialize(events:) — uses
        // the protocol-extension default.
    }

    @Test
    func `Default fallback short-circuit produces same result as tree path`() throws {
        let input = #"{"name":"Alice","age":30}"#
        let bytes: [UInt8] = Swift.Array(input.utf8)

        let viaTree = try FooDefault(jsonBytes: bytes)
        let viaEvents = try FooDefault.from(eventDecodingJsonBytes: bytes)

        #expect(viaTree.name == viaEvents.name)
        #expect(viaTree.age == viaEvents.age)
    }

    // MARK: - Opt-in event-grain wedge

    // FooEventGrain overrides deserialize(events:) and reads only the
    // declared fields, skipping the rest. This is the wedge that closes
    // the 37% gap.

    struct FooEventGrain: JSON.Serializable {
        let name: String

        static func serialize(_ value: FooEventGrain) -> JSON {
            ["name": .string(value.name)]
        }

        static func deserialize(_ json: JSON) throws(JSON.Error) -> FooEventGrain {
            let name = String(json.name)
            guard !name.isEmpty else {
                throw .missingKey("name")
            }
            return FooEventGrain(name: name)
        }

        static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> FooEventGrain {
            try events.expectObjectStart()
            var name: String? = nil
            while let token = try events.next() {
                if token == .objectEnd { break }
                guard token == .string else {
                    if token == .comma { continue }
                    throw .invalidSyntax(message: "expected key", location: events.position().location)
                }
                let key = try events.currentString()
                try events.expectColon()
                switch key {
                case "name":
                    name = try String.deserialize(events: &events)
                default:
                    try events.skipValue()
                }
            }
            guard let name = name else {
                throw .missingKey("name")
            }
            return FooEventGrain(name: name)
        }
    }

    @Test
    func `Opt-in event-grain reads only declared fields`() throws {
        let input = #"{"name":"Alice","age":30,"extra":[1,2,3,{"nested":true}],"ignored":"x"}"#
        let bytes: [UInt8] = Swift.Array(input.utf8)

        let result = try FooEventGrain.from(eventDecodingJsonBytes: bytes)
        #expect(result.name == "Alice")
    }

    @Test
    func `Opt-in event-grain handles missing declared field`() throws {
        let input = #"{"age":30,"extra":[1,2,3]}"#
        let bytes: [UInt8] = Swift.Array(input.utf8)

        do {
            _ = try FooEventGrain.from(eventDecodingJsonBytes: bytes)
            Issue.record("Expected missingKey error")
        } catch let error as JSON.Error {
            if case .missingKey(let key) = error {
                #expect(key == "name")
            } else {
                Issue.record("Wrong error: \(error)")
            }
        }
    }

    // MARK: - Entry point dispatch shapes

    @Test
    func `from eventDecodingJsonBytes works with contiguous ArraySlice`() throws {
        let bytes: [UInt8] = Swift.Array("42".utf8)
        let slice = bytes[0..<2]
        let result = try Int.from(eventDecodingJsonBytes: slice)
        #expect(result == 42)
    }

    @Test
    func `from eventDecodingJsonBytes works with ContiguousArray`() throws {
        let bytes = ContiguousArray<UInt8>("42".utf8)
        let result = try Int.from(eventDecodingJsonBytes: bytes)
        #expect(result == 42)
    }
}
