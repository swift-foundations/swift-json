/// JSON.Coder.Protocol Tests.swift
/// swift-json
///
/// Tests for JSON.Coder's Coder.Protocol-surface API.
///
/// Exercises the refined `parse(_:)` and `serialize(_:into:)` methods
/// directly (inherited via [FAM-006] from Parser.Protocol +
/// Serializer.Protocol) with the unified
/// `Either<RFC_8259.Error, JSON.Encode.Error>` failure type.

import Either_Primitives
import Testing

@testable import JSON

extension JSON.Coder {
    @Suite("JSON.Coder.Protocol")
    struct ProtocolTests {

        @Test
        func `parse via Coder.Protocol surface returns RFC_8259.Value`() throws {
            let bytes: [Byte] = "true".utf8.map(Byte.init)
            let coder = JSON.Coder()
            var span = bytes.span
            let value = try coder.parse(&span)
            let expected: RFC_8259.Value = true
            #expect(value == expected)
        }

        @Test
        func `parse via Coder.Protocol surface throws Either left on malformed JSON`() throws {
            let bytes: [Byte] = "{not json".utf8.map(Byte.init)
            let coder = JSON.Coder()
            var span = bytes.span
            do {
                _ = try coder.parse(&span)
                Issue.record("Expected parse to throw on malformed JSON")
            } catch let failure {
                switch failure {
                case .left:
                    break
                case .right:
                    Issue.record("Parse error should be Either.left (decode side), got .right")
                }
            }
        }

        @Test
        func `serialize via Coder.Protocol surface appends bytes to buffer`() throws {
            let coder = JSON.Coder()
            var buffer: [UInt8] = []
            let value: RFC_8259.Value = true
            try coder.serialize(value, into: &buffer)
            #expect(String(decoding: buffer, as: UTF8.self) == "true")
        }

        @Test
        func `round-trip via Coder.Protocol surface preserves value`() throws {
            let inputBytes: [Byte] = "[1,2,3]".utf8.map(Byte.init)
            let coder = JSON.Coder()

            var inputSpan = inputBytes.span
            let parsed = try coder.parse(&inputSpan)

            var outputBuffer: [UInt8] = []
            try coder.serialize(parsed, into: &outputBuffer)

            // serialize emits a `[UInt8]` Buffer; the parser consumes a
            // `Span<Byte>`. Bridge the encoder output to `[Byte]` for re-parse.
            let outputBytes: [Byte] = outputBuffer.map(Byte.init)
            var outputSpan = outputBytes.span
            let reparsed = try coder.parse(&outputSpan)

            #expect(parsed == reparsed)
        }
    }
}
