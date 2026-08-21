import RFC_8259

extension JSON {

    internal struct Decoder {

        internal let value: RFC_8259.Value

        internal let codingPath: [any CodingKey]

    }
}

extension JSON.Decoder: Swift.Decoder {

    internal var userInfo: [CodingUserInfoKey: Any] { [:] }

    internal func container<Key: CodingKey>(
        keyedBy type: Key.Type
    ) throws(DecodingError) -> KeyedDecodingContainer<Key> {
        guard case .object(let object) = value else {
            throw mismatch(KeyedDecodingContainer<Key>.self)
        }
        return KeyedDecodingContainer(
            JSON.Decoder.Keyed<Key>(object: object, codingPath: codingPath)
        )
    }

    internal func unkeyedContainer() throws(DecodingError) -> any UnkeyedDecodingContainer {
        guard case .array(let array) = value else {

            throw mismatch((any UnkeyedDecodingContainer).self)
        }
        return JSON.Decoder.Unkeyed(array: array, codingPath: codingPath)
    }

    internal func singleValueContainer() throws(DecodingError) -> any SingleValueDecodingContainer {
        JSON.Decoder.Single(decoder: self)
    }
}
