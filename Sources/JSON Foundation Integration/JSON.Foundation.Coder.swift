public import Coder_Primitives
public import Foundation
public import JSON

extension JSON.Foundation {
    /// A bidirectional JSON codec for values using Foundation's Codable system.
    ///
    /// The codec deliberately constructs a default `JSONDecoder` or `JSONEncoder`
    /// for each operation. This preserves Foundation's default wire behavior and
    /// keeps configuration policy out of the owner integration leaf.
    public struct Coder<Value: Swift.Codable>: Sendable {
        /// Creates a codec for `Value`.
        @inlinable
        public init(_ type: Value.Type = Value.self) {}
    }
}

extension JSON.Foundation.Coder: Coder_Primitives.Coder.`Protocol` {
    public typealias Input = Data
    public typealias Buffer = Data
    public typealias Output = Value
    public typealias Failure = JSON.Foundation.Error

    /// Decodes a value and consumes the complete input on success.
    public func parse(_ input: inout Data) throws(Failure) -> Value {
        do {
            let value = try JSONDecoder().decode(Value.self, from: input)
            input.removeAll(keepingCapacity: false)
            return value
        } catch {
            throw .decoding
        }
    }

    /// Encodes a value with Foundation's default JSON encoder and appends it.
    public func serialize(_ output: Value, into buffer: inout Data) throws(Failure) {
        do {
            let encoded = try JSONEncoder().encode(output)
            buffer.append(encoded)
        } catch {
            throw .encoding
        }
    }
}
