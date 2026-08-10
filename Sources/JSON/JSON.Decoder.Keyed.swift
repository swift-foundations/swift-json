/// JSON.Decoder.Keyed.swift
/// swift-json
///
/// The keyed decoding container over a JSON object.
///
/// ``RFC_8259/Object`` preserves insertion order and permits duplicate
/// member names, and its own subscript resolves a duplicate to the FIRST
/// occurrence. This container indexes the object once on construction with
/// the same first-wins rule, turning that O(n) subscript into O(1) lookups
/// without changing which value a name resolves to.

import RFC_8259

extension JSON.Decoder {
    /// A keyed decoding container reading members of a JSON object.
    internal struct Keyed<Key: CodingKey> {
        /// First-wins value per member name.
        internal let index: [String: RFC_8259.Value]

        /// Member names in insertion order, de-duplicated first-wins.
        internal let names: [String]

        // swiftlint:disable no_any_protocol_existential - `codingPath` is declared `[any CodingKey]` by `KeyedDecodingContainerProtocol`; the storage and the initializer that seeds it must spell the stdlib's element type (stdlib; rule-exemptions protocol-requirement shape)

        /// The path of coding keys taken to reach this container.
        internal let codingPath: [any CodingKey]

        /// Creates a container over `object`, indexing it first-wins.
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

        // swiftlint:enable no_any_protocol_existential
    }
}

// MARK: - Child decoders

extension JSON.Decoder.Keyed {
    /// The decoder for the value stored under `key`.
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

// MARK: - KeyedDecodingContainerProtocol conformance

extension JSON.Decoder.Keyed: KeyedDecodingContainerProtocol {
    /// The member names this container can decode, in insertion order.
    ///
    /// Names the caller's `Key` type cannot represent are omitted, which is
    /// the same contract Swift's own keyed containers observe.
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

    // swiftlint:disable no_any_protocol_existential - exact `KeyedDecodingContainerProtocol` requirement signature; the existential return type is the stdlib's (stdlib; rule-exemptions protocol-requirement shape)
    internal func nestedUnkeyedContainer(
        forKey key: Key
    ) throws(DecodingError) -> any UnkeyedDecodingContainer {
        try decoder(for: key).unkeyedContainer()
    }
    // swiftlint:enable no_any_protocol_existential

    // swiftlint:disable:next no_any_protocol_existential - exact `Swift.Decoder` requirement signature (stdlib; rule-exemptions protocol-requirement shape)
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

    // swiftlint:disable:next no_any_protocol_existential - exact `Swift.Decoder` requirement signature (stdlib; rule-exemptions protocol-requirement shape)
    internal func superDecoder(forKey key: Key) throws(DecodingError) -> any Swift.Decoder {
        try decoder(for: key)
    }
}
