public import Coder_Primitives
public import Either_Primitives
public import RFC_8259

extension JSON {

    public struct Coder: Sendable {

        public let maxDepth: Int

        public let encodeOptions: JSON.Encode.Options

        @inlinable
        public init(
            maxDepth: Int = 512,
            encodeOptions: JSON.Encode.Options = JSON.Encode.Options()
        ) {
            self.maxDepth = maxDepth
            self.encodeOptions = encodeOptions
        }
    }
}

extension JSON.Coder: Coder_Primitives.Coder.`Protocol` {
    public typealias Input = Swift.Span<Byte>
    public typealias Buffer = [UInt8]
    public typealias Output = RFC_8259.Value
    public typealias Failure = Either<RFC_8259.Error, JSON.Encode.Error>

    @inlinable
    public func parse(
        _ input: inout Swift.Span<Byte>
    ) throws(Failure) -> RFC_8259.Value {
        let value: RFC_8259.Value
        do throws(RFC_8259.Error) {
            value = try JSON.Decode.Implementation.parse(input, maxDepth: maxDepth)
        } catch {
            throw .left(error)
        }

        input = input.extracting(input.count..<input.count)
        return value
    }

    @inlinable
    public func serialize(
        _ output: RFC_8259.Value,
        into buffer: inout [UInt8]
    ) throws(Failure) {
        var encoder = JSON.Encode.Encoder(options: encodeOptions)
        do throws(JSON.Encode.Error) {
            try encoder.encode(output, into: &buffer)
        } catch {
            throw .right(error)
        }
    }
}

extension RFC_8259.Value: @retroactive Coder_Primitives.Coder.Codable {

    public typealias Coder = JSON.Coder

    @inlinable
    public static var coder: JSON.Coder { JSON.Coder() }
}
