public import Coder_Primitives
public import Foundation
public import JSON

extension JSON.Foundation {

    public struct Coder<Value: Swift.Codable>: Sendable {

        @inlinable
        public init(_ type: Value.Type = Value.self) {}
    }
}

extension JSON.Foundation.Coder: Coder_Primitives.Coder.`Protocol` {
    public typealias Input = Data
    public typealias Buffer = Data
    public typealias Output = Value
    public typealias Failure = JSON.Foundation.Error

    public func parse(_ input: inout Data) throws(Failure) -> Value {
        do {
            let value = try JSONDecoder().decode(Value.self, from: input)
            input.removeAll(keepingCapacity: false)
            return value
        } catch {
            throw .decoding
        }
    }

    public func serialize(_ output: Value, into buffer: inout Data) throws(Failure) {
        do {
            let encoded = try JSONEncoder().encode(output)
            buffer.append(encoded)
        } catch {
            throw .encoding
        }
    }
}
