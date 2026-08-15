/// JSON.Decoder.Single.swift
/// swift-json
///
/// The single-value decoding container.
///
/// A thin forwarder: the decoder it wraps is already positioned at exactly
/// the value this container reads, so every requirement delegates without
/// locating anything first.

extension JSON.Decoder {
    /// A single-value decoding container over one JSON value.
    internal struct Single {
        /// The decoder positioned at the value being read.
        internal let decoder: JSON.Decoder
    }
}

// MARK: - SingleValueDecodingContainer conformance

extension JSON.Decoder.Single: SingleValueDecodingContainer {
    // swiftlint:disable:next no_any_protocol_existential - `codingPath` is declared `[any CodingKey]` by the stdlib container protocols (stdlib; rule-exemptions protocol-requirement shape)
    internal var codingPath: [any CodingKey] { decoder.codingPath }

    internal func decodeNil() -> Bool { decoder.value.isNull }

    internal func decode(_ type: Bool.Type) throws(DecodingError) -> Bool {
        try decoder.bool()
    }

    internal func decode(_ type: String.Type) throws(DecodingError) -> String {
        try decoder.string()
    }

    internal func decode(_ type: Double.Type) throws(DecodingError) -> Double {
        try decoder.floating(type)
    }

    internal func decode(_ type: Float.Type) throws(DecodingError) -> Float {
        try decoder.floating(type)
    }

    internal func decode(_ type: Int.Type) throws(DecodingError) -> Int {
        try decoder.integer(type)
    }

    internal func decode(_ type: Int8.Type) throws(DecodingError) -> Int8 {
        try decoder.integer(type)
    }

    internal func decode(_ type: Int16.Type) throws(DecodingError) -> Int16 {
        try decoder.integer(type)
    }

    internal func decode(_ type: Int32.Type) throws(DecodingError) -> Int32 {
        try decoder.integer(type)
    }

    internal func decode(_ type: Int64.Type) throws(DecodingError) -> Int64 {
        try decoder.integer(type)
    }

    internal func decode(_ type: UInt.Type) throws(DecodingError) -> UInt {
        try decoder.integer(type)
    }

    internal func decode(_ type: UInt8.Type) throws(DecodingError) -> UInt8 {
        try decoder.integer(type)
    }

    internal func decode(_ type: UInt16.Type) throws(DecodingError) -> UInt16 {
        try decoder.integer(type)
    }

    internal func decode(_ type: UInt32.Type) throws(DecodingError) -> UInt32 {
        try decoder.integer(type)
    }

    internal func decode(_ type: UInt64.Type) throws(DecodingError) -> UInt64 {
        try decoder.integer(type)
    }

    internal func decode<T: Swift.Decodable>(_ type: T.Type) throws(DecodingError) -> T {
        try decoder.decoded(type)
    }
}
