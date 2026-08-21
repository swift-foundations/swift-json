import RFC_8259

extension JSON.Decoder {

    internal struct Unkeyed {

        internal let array: RFC_8259.Array

        internal let codingPath: [any CodingKey]

        internal var currentIndex: Int

        internal init(array: RFC_8259.Array, codingPath: [any CodingKey]) {
            self.array = array
            self.codingPath = codingPath
            self.currentIndex = array.startIndex
        }

    }
}

extension JSON.Decoder.Unkeyed {

    internal func peek<T>(_ type: T.Type) throws(DecodingError) -> JSON.Decoder {
        guard !isAtEnd else { throw exhausted(type) }
        return JSON.Decoder(
            value: array[currentIndex],
            codingPath: codingPath + [JSON.Decoder.Key.index(currentIndex)]
        )
    }

    internal mutating func advance() {
        currentIndex = array.index(after: currentIndex)
    }

    internal func exhausted<T>(_ type: T.Type) -> DecodingError {
        .valueNotFound(
            type,
            DecodingError.Context(
                codingPath: codingPath + [JSON.Decoder.Key.index(currentIndex)],
                debugDescription:
                    "Unkeyed container is at end: \(array.count) element(s) available."
            )
        )
    }
}

extension JSON.Decoder.Unkeyed: UnkeyedDecodingContainer {
    internal var count: Int? { array.count }

    internal var isAtEnd: Bool { currentIndex >= array.endIndex }

    internal mutating func decodeNil() throws(DecodingError) -> Bool {
        guard !isAtEnd else { throw exhausted(Any?.self) }
        guard array[currentIndex].isNull else { return false }
        advance()
        return true
    }

    internal mutating func decode(_ type: Bool.Type) throws(DecodingError) -> Bool {
        let decoded = try peek(type).bool()
        advance()
        return decoded
    }

    internal mutating func decode(_ type: String.Type) throws(DecodingError) -> String {
        let decoded = try peek(type).string()
        advance()
        return decoded
    }

    internal mutating func decode(_ type: Double.Type) throws(DecodingError) -> Double {
        let decoded = try peek(type).floating(type)
        advance()
        return decoded
    }

    internal mutating func decode(_ type: Float.Type) throws(DecodingError) -> Float {
        let decoded = try peek(type).floating(type)
        advance()
        return decoded
    }

    internal mutating func decode(_ type: Int.Type) throws(DecodingError) -> Int {
        let decoded = try peek(type).integer(type)
        advance()
        return decoded
    }

    internal mutating func decode(_ type: Int8.Type) throws(DecodingError) -> Int8 {
        let decoded = try peek(type).integer(type)
        advance()
        return decoded
    }

    internal mutating func decode(_ type: Int16.Type) throws(DecodingError) -> Int16 {
        let decoded = try peek(type).integer(type)
        advance()
        return decoded
    }

    internal mutating func decode(_ type: Int32.Type) throws(DecodingError) -> Int32 {
        let decoded = try peek(type).integer(type)
        advance()
        return decoded
    }

    internal mutating func decode(_ type: Int64.Type) throws(DecodingError) -> Int64 {
        let decoded = try peek(type).integer(type)
        advance()
        return decoded
    }

    internal mutating func decode(_ type: UInt.Type) throws(DecodingError) -> UInt {
        let decoded = try peek(type).integer(type)
        advance()
        return decoded
    }

    internal mutating func decode(_ type: UInt8.Type) throws(DecodingError) -> UInt8 {
        let decoded = try peek(type).integer(type)
        advance()
        return decoded
    }

    internal mutating func decode(_ type: UInt16.Type) throws(DecodingError) -> UInt16 {
        let decoded = try peek(type).integer(type)
        advance()
        return decoded
    }

    internal mutating func decode(_ type: UInt32.Type) throws(DecodingError) -> UInt32 {
        let decoded = try peek(type).integer(type)
        advance()
        return decoded
    }

    internal mutating func decode(_ type: UInt64.Type) throws(DecodingError) -> UInt64 {
        let decoded = try peek(type).integer(type)
        advance()
        return decoded
    }

    internal mutating func decode<T: Swift.Decodable>(
        _ type: T.Type
    ) throws(DecodingError) -> T {
        let decoded = try peek(type).decoded(type)
        advance()
        return decoded
    }

    internal mutating func nestedContainer<Nested: CodingKey>(
        keyedBy type: Nested.Type
    ) throws(DecodingError) -> KeyedDecodingContainer<Nested> {
        let container = try peek(KeyedDecodingContainer<Nested>.self)
            .container(keyedBy: type)
        advance()
        return container
    }

    internal mutating func nestedUnkeyedContainer()
        throws(DecodingError) -> any UnkeyedDecodingContainer
    {
        let container = try peek((any UnkeyedDecodingContainer).self)
            .unkeyedContainer()
        advance()
        return container
    }

    internal mutating func superDecoder() throws(DecodingError) -> any Swift.Decoder {

        let decoder = try peek((any Swift.Decoder).self)
        advance()
        return decoder
    }
}
