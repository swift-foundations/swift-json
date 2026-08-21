import Testing

@testable import JSON

extension JSON.Assemble {
    @Suite
    struct Test {

        @Test
        func `Assemble.from short-circuits at position 0 and returns parsed value`() throws {
            let bytes: [Byte] = #"{"name":"alice","age":30,"tags":["x","y"]}"#.utf8.map(Byte.init)
            try bytes.withUnsafeBufferPointer {
                (buf: UnsafeBufferPointer<Byte>) throws(RFC_8259.Error) in
                let span = buf.span
                var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
                let unforkedBefore: Bool = stream.isPristine
                #expect(unforkedBefore)
                let value = try Lexer.Pull.Assemble.from(&stream, strategy: JSON.Assemble.self)

                let unforkedAfter: Bool = stream.isPristine
                #expect(!unforkedAfter)

                #expect(value.object != nil)
                #expect(value["name"]?.string == "alice")
                #expect(value["age"]?.number?.int64 == 30)
                #expect(value["tags"]?.array?.count == 2)
            }
        }

        @Test
        func `Assemble.from slow path after partial advance rebuilds via events`() throws {

            let bytes: [Byte] = #"[1,2,3]"#.utf8.map(Byte.init)
            try bytes.withUnsafeBufferPointer {
                (buf: UnsafeBufferPointer<Byte>) throws(RFC_8259.Error) in
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
            try bytes.withUnsafeBufferPointer {
                (buf: UnsafeBufferPointer<Byte>) throws(RFC_8259.Error) in
                let span = buf.span
                var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
                let value = try Lexer.Pull.Assemble.from(&stream, strategy: JSON.Assemble.self)
                #expect(value.isNull)
            }
        }

        @Test
        func `Assemble.from output matches public JSON.Decode.parse output`() throws {

            let bytes: [Byte] = #"{"a":1,"b":[true,null,"s"]}"#.utf8.map(Byte.init)
            let direct = try JSON.Decode.parse(bytes)
            try bytes.withUnsafeBufferPointer {
                (buf: UnsafeBufferPointer<Byte>) throws(RFC_8259.Error) in
                let span = buf.span
                var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
                let assembled = try Lexer.Pull.Assemble.from(&stream, strategy: JSON.Assemble.self)
                #expect(direct == assembled)
            }
        }
    }
}
