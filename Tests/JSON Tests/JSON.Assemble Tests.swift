/// JSON.Assemble Tests.swift
/// swift-json
///
/// Tests for `JSON.Assemble` — the JSON-specific assemble strategy
/// for the L1 ``Lexer/Pull/Assemble`` cohort. Implements
/// ``Lexer/Pull/Assemble/Strategy`` (internally) for `RFC_8259.Value`.
///
/// Coverage:
/// - FAST PATH: `Lexer.Pull.Assemble.from(_:strategy:)` short-circuits
///   through `JSON.Assemble.consume(bytes:limit:)` when the stream is
///   pristine.
/// - SLOW PATH: `JSON.Assemble.build(events:)` rebuilds the tree by
///   driving the event stream forward after a partial advance.
/// - Round-trip: consume(bytes:limit:) and build(events:) on a fresh
///   stream produce the same value on the same bytes.
///
/// Relocated from swift-rfc-8259/Tests under Arc 1.5 — the strategy
/// being tested is implementation, not spec, so the tests live at L3.

import Testing

@testable import JSON

extension JSON.Assemble {
    @Suite("JSON Assemble Tests")
    struct Tests {

        @Test
        func `Assemble.from short-circuits at position 0 and returns parsed value`() throws {
            let bytes: [Byte] = #"{"name":"alice","age":30,"tags":["x","y"]}"#.utf8.map(Byte.init)
            try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<Byte>) throws(RFC_8259.Error) in
                let span = buf.span
                var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
                let unforkedBefore: Bool = stream.isPristine
                #expect(unforkedBefore)
                let value = try Lexer.Pull.Assemble.from(&stream, strategy: JSON.Assemble.self)
                // The short-circuit fully consumed the stream.
                let unforkedAfter: Bool = stream.isPristine
                #expect(!unforkedAfter)
                // Verify object structure.
                #expect(value.object != nil)
                #expect(value["name"]?.string == "alice")
                #expect(value["age"]?.number?.int64 == 30)
                #expect(value["tags"]?.array?.count == 2)
            }
        }

        @Test
        func `Assemble.from slow path after partial advance rebuilds via events`() throws {
            // Pull one event manually before calling Assemble.from so that
            // isPristine becomes false; the helper then routes
            // through the slow event-pull-and-rebuild path.
            let bytes: [Byte] = #"[1,2,3]"#.utf8.map(Byte.init)
            try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<Byte>) throws(RFC_8259.Error) in
                let span = buf.span
                var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
                let firstToken = try stream.next()
                #expect(firstToken == .arrayStart)
                let unforkedAfterAdvance: Bool = stream.isPristine
                #expect(!unforkedAfterAdvance)
                let value = try Lexer.Pull.Assemble.from(&stream, strategy: JSON.Assemble.self)
                #expect(value.number?.int64 == 1)
            }
        }

        @Test
        func `Assemble.from on null produces .null value`() throws {
            let bytes: [Byte] = "null".utf8.map(Byte.init)
            try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<Byte>) throws(RFC_8259.Error) in
                let span = buf.span
                var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
                let value = try Lexer.Pull.Assemble.from(&stream, strategy: JSON.Assemble.self)
                #expect(value.isNull)
            }
        }

        @Test
        func `Assemble.from output matches public JSON.Decode.parse output`() throws {
            // Round-trip: the assembler's output via Assemble.from MUST
            // equal the public `JSON.Decode.parse(_:)` output on the same bytes.
            let bytes: [Byte] = #"{"a":1,"b":[true,null,"s"]}"#.utf8.map(Byte.init)
            let direct = try JSON.Decode.parse(bytes)
            try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<Byte>) throws(RFC_8259.Error) in
                let span = buf.span
                var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
                let assembled = try Lexer.Pull.Assemble.from(&stream, strategy: JSON.Assemble.self)
                #expect(direct == assembled)
            }
        }
    }
}
