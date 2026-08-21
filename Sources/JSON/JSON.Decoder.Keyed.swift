import RFC_8259

extension JSON.Decoder {

    internal struct Keyed<Key: CodingKey> {

        internal let index: [String: RFC_8259.Value]

        internal let names: [String]

        internal let codingPath: [any CodingKey]

        internal init(object: RFC_8259.Object, codingPath: [any CodingKey]) {
            var index: [String: RFC_8259.Value] = [:]
            var names: [String] = []
            index.reserveCapacity(object.count)
            names.reserveCapacity(object.count)
            for member in object where index[member.key] == nil {
                index[member.key] = member.value
                names.append(member.key)
            }
            self.index = index
            self.names = names
            self.codingPath = codingPath
        }

    }
}

extension JSON.Decoder.Keyed {

    internal func decoder(for key: Key) throws(DecodingError) -> JSON.Decoder {
        guard let found = index[key.stringValue] else {
            throw .keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription:
                        "No value associated with key \(key.stringValue)."
                )
            )
        }
        return JSON.Decoder(value: found, codingPath: codingPath + [key])
    }
}

extension JSON.Decoder.Keyed: KeyedDecodingContainerProtocol {

    internal var allKeys: [Key] {
        names.compactMap(Key.init(stringValue:))
    }

    internal func contains(_ key: Key) -> Bool {
        index[key.stringValue] != nil
    }

    internal func decodeNil(forKey key: Key) throws(DecodingError) -> Bool {
        try decoder(for: key).value.isNull
    }

    internal func decode(_ type: Bool.Type, forKey key: Key) throws(DecodingError) -> Bool {
        try decoder(for: key).bool()
    }

    internal func decode(_ type: String.Type, forKey key: Key) throws(DecodingError) -> String {
        try decoder(for: key).string()
    }

    internal func decode(_ type: Double.Type, forKey key: Key) throws(DecodingError) -> Double {
        try decoder(for: key).floating(type)
    }

    internal func decode(_ type: Float.Type, forKey key: Key) throws(DecodingError) -> Float {
        try decoder(for: key).floating(type)
    }

    internal func decode(_ type: Int.Type, forKey key: Key) throws(DecodingError) -> Int {
        try decoder(for: key).integer(type)
    }

    internal func decode(_ type: Int8.Type, forKey key: Key) throws(DecodingError) -> Int8 {
        try decoder(for: key).integer(type)
    }

    internal func decode(_ type: Int16.Type, forKey key: Key) throws(DecodingError) -> Int16 {
        try decoder(for: key).integer(type)
    }

    internal func decode(_ type: Int32.Type, forKey key: Key) throws(DecodingError) -> Int32 {
        try decoder(for: key).integer(type)
    }

    internal func decode(_ type: Int64.Type, forKey key: Key) throws(DecodingError) -> Int64 {
        try decoder(for: key).integer(type)
    }

    internal func decode(_ type: UInt.Type, forKey key: Key) throws(DecodingError) -> UInt {
        try decoder(for: key).integer(type)
    }

    internal func decode(_ type: UInt8.Type, forKey key: Key) throws(DecodingError) -> UInt8 {
        try decoder(for: key).integer(type)
    }

    internal func decode(_ type: UInt16.Type, forKey key: Key) throws(DecodingError) -> UInt16 {
        try decoder(for: key).integer(type)
    }

    internal func decode(_ type: UInt32.Type, forKey key: Key) throws(DecodingError) -> UInt32 {
        try decoder(for: key).integer(type)
    }

    internal func decode(_ type: UInt64.Type, forKey key: Key) throws(DecodingError) -> UInt64 {
        try decoder(for: key).integer(type)
    }

    internal func decode<T: Swift.Decodable>(
        _ type: T.Type,
        forKey key: Key
    ) throws(DecodingError) -> T {
        try decoder(for: key).decoded(type)
    }

    internal func nestedContainer<Nested: CodingKey>(
        keyedBy type: Nested.Type,
        forKey key: Key
    ) throws(DecodingError) -> KeyedDecodingContainer<Nested> {
        try decoder(for: key).container(keyedBy: type)
    }

    internal func nestedUnkeyedContainer(
        forKey key: Key
    ) throws(DecodingError) -> any UnkeyedDecodingContainer {
        try decoder(for: key).unkeyedContainer()
    }

    internal func superDecoder() throws(DecodingError) -> any Swift.Decoder {
        let key = JSON.Decoder.Key.super
        guard let found = index[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription:
                        "No superclass value associated with key \(key.stringValue)."
                )
            )
        }
        return JSON.Decoder(value: found, codingPath: codingPath + [key])
    }

    internal func superDecoder(forKey key: Key) throws(DecodingError) -> any Swift.Decoder {
        try decoder(for: key)
    }
}
