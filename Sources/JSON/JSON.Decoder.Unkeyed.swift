/// JSON.Decoder.Unkeyed.swift
/// swift-json
///
/// The unkeyed decoding container over a JSON array.
///
/// The cursor advances only on a successful read. `decodeNil()` is the one
/// deliberate asymmetry: it advances when the element IS null and leaves
/// the cursor alone when it is not, so a caller may probe for null and then
/// decode the same element as a concrete type.

import RFC_8259

extension JSON.Decoder {
    /// An unkeyed decoding container reading elements of a JSON array.
    internal struct Unkeyed {
        /// The array being read.
        internal let array: RFC_8259.Array

        /// The path of coding keys taken to reach this container.
        internal let codingPath: [any CodingKey]

        /// The position of the next element to read.
        internal var currentIndex: Int

        /// Creates a container positioned at the array's first element.
        internal init(array: RFC_8259.Array, codingPath: [any CodingKey]) {
            self.array = array
            self.codingPath = codingPath
            self.currentIndex = array.startIndex
        }
    }
}

// MARK: - Child decoders

extension JSON.Decoder.Unkeyed {
    /// The decoder for the next element, advancing past it.
    ///
    /// `type` names the value the caller asked for, so exhausting the
    /// container reports which decode ran off the end.
    internal mutating func next<T>(
        _ type: T.Type
    ) throws(DecodingError) -> JSON.Decoder {
        guard !isAtEnd else { throw exhausted(type) }
        let key = JSON.Decoder.Key.index(currentIndex)
        let decoder = JSON.Decoder(
            value: array[currentIndex],
            codingPath: codingPath + [key]
        )
        currentIndex = array.index(after: currentIndex)
        return decoder
    }

    /// The error for a read past the final element.
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

// MARK: - UnkeyedDecodingContainer conformance

extension JSON.Decoder.Unkeyed: UnkeyedDecodingContainer {
    internal var count: Int? { array.count }

    internal var isAtEnd: Bool { currentIndex >= array.endIndex }

    internal mutating func decodeNil() throws(DecodingError) ->Bool {
        guard !isAtEnd else { throw exhausted(Any?.self) }
        guard array[currentIndex].isNull else { return false }
        currentIndex = array.index(after: currentIndex)
        return true
    }

    internal mutating func decode(_ type: Bool.Type) throws(DecodingError) ->Bool {
        try next(type).bool()
    }

    internal mutating func decode(_ type: String.Type) throws(DecodingError) ->String {
        try next(type).string()
    }

    internal mutating func decode(_ type: Double.Type) throws(DecodingError) ->Double {
        try next(type).floating(type)
    }

    internal mutating func decode(_ type: Float.Type) throws(DecodingError) ->Float {
        try next(type).floating(type)
    }

    internal mutating func decode(_ type: Int.Type) throws(DecodingError) ->Int {
        try next(type).integer(type)
    }

    internal mutating func decode(_ type: Int8.Type) throws(DecodingError) ->Int8 {
        try next(type).integer(type)
    }

    internal mutating func decode(_ type: Int16.Type) throws(DecodingError) ->Int16 {
        try next(type).integer(type)
    }

    internal mutating func decode(_ type: Int32.Type) throws(DecodingError) ->Int32 {
        try next(type).integer(type)
    }

    internal mutating func decode(_ type: Int64.Type) throws(DecodingError) ->Int64 {
        try next(type).integer(type)
    }

    internal mutating func decode(_ type: UInt.Type) throws(DecodingError) ->UInt {
        try next(type).integer(type)
    }

    internal mutating func decode(_ type: UInt8.Type) throws(DecodingError) ->UInt8 {
        try next(type).integer(type)
    }

    internal mutating func decode(_ type: UInt16.Type) throws(DecodingError) ->UInt16 {
        try next(type).integer(type)
    }

    internal mutating func decode(_ type: UInt32.Type) throws(DecodingError) ->UInt32 {
        try next(type).integer(type)
    }

    internal mutating func decode(_ type: UInt64.Type) throws(DecodingError) ->UInt64 {
        try next(type).integer(type)
    }

    internal mutating func decode<T: Swift.Decodable>(_ type: T.Type) throws(DecodingError) ->T {
        try next(type).decoded(type)
    }

    internal mutating func nestedContainer<Nested: CodingKey>(
        keyedBy type: Nested.Type
    ) throws(DecodingError) ->KeyedDecodingContainer<Nested> {
        try next(KeyedDecodingContainer<Nested>.self).container(keyedBy: type)
    }

    internal mutating func nestedUnkeyedContainer()
        throws(DecodingError) -> any UnkeyedDecodingContainer
    {
        try next((any UnkeyedDecodingContainer).self).unkeyedContainer()
    }

    internal mutating func superDecoder() throws(DecodingError) ->any Swift.Decoder {
        try next((any Swift.Decoder).self)
    }
}
