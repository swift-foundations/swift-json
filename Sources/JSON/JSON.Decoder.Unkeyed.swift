/// JSON.Decoder.Unkeyed.swift
/// swift-json
///
/// The unkeyed decoding container over a JSON array.
///
/// The cursor advances only after a decode SUCCEEDS. A failed decode leaves
/// the element unconsumed, so a caller that catches the error can retry the
/// same position with a different type — the behaviour `Swift.Decodable`
/// conformers rely on when they probe a heterogeneous array. Locating the
/// element (``peek(_:)``) is therefore separated from consuming it
/// (``advance()``), and every requirement below performs them in that order.
///
/// ``decodeNil()`` is the one deliberate asymmetry, and it is a probe by
/// design: it consumes the element when it IS null and leaves the cursor
/// alone when it is not.

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

// MARK: - Locating and consuming

extension JSON.Decoder.Unkeyed {
    /// The decoder for the next element, WITHOUT consuming it.
    ///
    /// `type` names the value the caller asked for, so exhausting the
    /// container reports which decode ran off the end.
    internal func peek<T>(_ type: T.Type) throws(DecodingError) -> JSON.Decoder {
        guard !isAtEnd else { throw exhausted(type) }
        return JSON.Decoder(
            value: array[currentIndex],
            codingPath: codingPath + [JSON.Decoder.Key.index(currentIndex)]
        )
    }

    /// Consumes the element that was just decoded successfully.
    internal mutating func advance() {
        currentIndex = array.index(after: currentIndex)
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
