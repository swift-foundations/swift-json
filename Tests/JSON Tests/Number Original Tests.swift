import Testing

@testable import JSON

@Suite
struct `Number Original` {
    @Suite struct `Pull Stream` {}
    @Suite struct `Decode` {}
}

private func pullNumber(_ text: String) throws -> RFC_8259.Number {
    let bytes: [Byte] = text.utf8.map(Byte.init)
    return try bytes.withUnsafeBufferPointer {
        (buf: UnsafeBufferPointer<Byte>) throws(RFC_8259.Error) -> RFC_8259.Number in
        let span = buf.span
        var stream = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(span)
        _ = try stream.next()
        return try stream.currentNumber()
    }
}

private func decodeNumber(_ text: String) throws -> RFC_8259.Number {
    let bytes: [Byte] = text.utf8.map(Byte.init)
    let value = try JSON.Decode.parse(bytes)
    guard case .number(let number) = value else {
        Issue.record("expected a number, got \(value)")
        return RFC_8259.Number(Int64(0), original: .init([Byte]()))
    }
    return number
}

private let twentyThreeDigits = String(repeating: "1", count: 23)
private let twentyFourDigits = String(repeating: "1", count: 24)
private let fortyDigits = String(repeating: "9", count: 40)

extension `Number Original`.`Pull Stream` {
    @Test(arguments: [
        "0",
        "42",
        "-123",
        "3.14",
        "1.5e10",

        "-0",
        "1.50",
        "1e5",
        "1E+5",
        "0.0000000000001",
    ])
    func `Original preserves the verbatim text`(text: String) throws {
        let number = try pullNumber(text)
        #expect(number.original.string == text)
    }

    @Test
    func `Original preserves text across the inline heap boundary`() throws {

        for text in [twentyThreeDigits, twentyFourDigits, fortyDigits] {
            let number = try pullNumber(text)
            #expect(number.original.string == text)
            #expect(number.original.bytes.count == text.utf8.count)
        }
    }

    @Test
    func `Integer widens through Int64 then UInt64 then Double`() throws {

        let signed = try pullNumber("9223372036854775807")
        #expect(signed.int64 == Int64.max)

        let unsigned = try pullNumber("18446744073709551615")
        #expect(unsigned.int64 == nil)
        #expect(unsigned.uint64 == UInt64.max)

        let huge = try pullNumber(fortyDigits)
        #expect(huge.int64 == nil)
        #expect(huge.uint64 == nil)
        #expect(huge.double == Double(fortyDigits))
        #expect(huge.original.string == fortyDigits)
    }

    @Test
    func `Negative integer bounds survive`() throws {
        let number = try pullNumber("-9223372036854775808")
        #expect(number.int64 == Int64.min)
        #expect(number.original.string == "-9223372036854775808")
    }
}

extension `Number Original`.Decode {
    @Test(arguments: [
        "0",
        "42",
        "-123",
        "3.14",
        "1.5e10",
        "-0",
        "1.50",
        "1e5",
        "0.0000000000001",
    ])
    func `Original preserves the verbatim text`(text: String) throws {
        let number = try decodeNumber(text)
        #expect(number.original.string == text)
    }

    @Test
    func `Original preserves text across the inline heap boundary`() throws {
        for text in [twentyThreeDigits, twentyFourDigits, fortyDigits] {
            let number = try decodeNumber(text)
            #expect(number.original.string == text)
            #expect(number.original.bytes.count == text.utf8.count)
        }
    }

    @Test
    func `Integer widens through Int64 then UInt64 then Double`() throws {
        let signed = try decodeNumber("9223372036854775807")
        #expect(signed.int64 == Int64.max)

        let unsigned = try decodeNumber("18446744073709551615")
        #expect(unsigned.int64 == nil)
        #expect(unsigned.uint64 == UInt64.max)

        let huge = try decodeNumber(fortyDigits)
        #expect(huge.int64 == nil)
        #expect(huge.uint64 == nil)
        #expect(huge.double == Double(fortyDigits))
        #expect(huge.original.string == fortyDigits)
    }
}
