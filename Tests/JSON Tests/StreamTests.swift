/// StreamTests.swift
/// swift-json

import Testing

@testable import JSON

@Suite("Stream Tests")
struct StreamTests {

    // MARK: - NDJSON Streaming

    @Test
    func `Parse NDJSON stream`() async throws {
        let input = """
            {"id":1}
            {"id":2}
            {"id":3}
            """

        let bytes = AsyncStream<UInt8> { continuation in
            for byte in input.utf8 {
                continuation.yield(byte)
            }
            continuation.finish()
        }

        var ids: [Int] = []
        for await result in JSON.ND.stream(bytes) {
            let json = try result.get()
            if let id = Int(json.id) {
                ids.append(id)
            }
        }

        #expect(ids == [1, 2, 3])
    }

    @Test
    func `Skip empty lines in NDJSON`() async throws {
        let input = """
            {"id":1}

            {"id":2}

            """

        let bytes = AsyncStream<UInt8> { continuation in
            for byte in input.utf8 {
                continuation.yield(byte)
            }
            continuation.finish()
        }

        var ids: [Int] = []
        for await result in JSON.ND.stream(bytes) {
            let json = try result.get()
            if let id = Int(json.id) {
                ids.append(id)
            }
        }

        #expect(ids == [1, 2])
    }

    @Test
    func `Continue after malformed line`() async {
        let input = """
            {"id":1}
            not json
            {"id":3}
            """

        let bytes = AsyncStream<UInt8> { continuation in
            for byte in input.utf8 {
                continuation.yield(byte)
            }
            continuation.finish()
        }

        var successes: [Int] = []
        var failures = 0

        for await result in JSON.ND.stream(bytes) {
            switch result {
            case .success(let json):
                if let id = Int(json.id) {
                    successes.append(id)
                }
            case .failure:
                failures += 1
            }
        }

        #expect(successes == [1, 3])
        #expect(failures == 1)
    }

    @Test
    func `Handle CRLF line endings`() async throws {
        let input = "{\"id\":1}\r\n{\"id\":2}\r\n"

        let bytes = AsyncStream<UInt8> { continuation in
            for byte in input.utf8 {
                continuation.yield(byte)
            }
            continuation.finish()
        }

        var ids: [Int] = []
        for await result in JSON.ND.stream(bytes) {
            let json = try result.get()
            if let id = Int(json.id) {
                ids.append(id)
            }
        }

        #expect(ids == [1, 2])
    }

    @Test
    func `Parse without trailing newline`() async throws {
        let input = "{\"id\":1}\n{\"id\":2}"

        let bytes = AsyncStream<UInt8> { continuation in
            for byte in input.utf8 {
                continuation.yield(byte)
            }
            continuation.finish()
        }

        var ids: [Int] = []
        for await result in JSON.ND.stream(bytes) {
            let json = try result.get()
            if let id = Int(json.id) {
                ids.append(id)
            }
        }

        #expect(ids == [1, 2])
    }

    // MARK: - Single Document Async Parse

    @Test
    func `Parse single document from async bytes`() async throws {
        let input = #"{"name": "John", "age": 30}"#

        let bytes = AsyncStream<UInt8> { continuation in
            for byte in input.utf8 {
                continuation.yield(byte)
            }
            continuation.finish()
        }

        let json = try await JSON.parse(collecting: bytes)

        #expect(String(json.name) == "John")
        #expect(Int(json.age) == 30)
    }

    @Test
    func `Parse empty async stream`() async {
        let bytes = AsyncStream<UInt8> { continuation in
            continuation.finish()
        }

        do throws(JSON.Error) {
            _ = try await JSON.parse(collecting: bytes)
            Issue.record("Expected error for empty input")
        } catch {
            // Expected
        }
    }

    // MARK: - JSON.Serializable Async

    @Test
    func `Deserialize from async bytes`() async throws {
        let input = "[1, 2, 3]"

        let bytes = AsyncStream<UInt8> { continuation in
            for byte in input.utf8 {
                continuation.yield(byte)
            }
            continuation.finish()
        }

        let array = try await [Int](collecting: bytes)

        #expect(array == [1, 2, 3])
    }
}
