/// JSON+Decoder.swift
/// swift-json
///
/// The public entry point for `Swift.Decodable` decoding.
///
/// Pairs with ``JSON/parse(_:)-String``: parse bytes into a ``JSON`` value,
/// then decode that value into a `Decodable` type. Nothing here parses, and
/// nothing here touches Foundation — see ``JSON/Decoder`` for why a
/// `Swift.Decoder` exists alongside ``JSON/Serializable``.

extension JSON {
    /// Decodes a `Decodable` value from this JSON value.
    ///
    /// ```swift
    /// let json = try JSON.parse(#"{"name":"swift","stars":3}"#)
    /// let package = try json.decode(Package.self)
    /// ```
    ///
    /// - Parameter type: The type to decode. Inferable from context.
    /// - Returns: The decoded value.
    /// - Throws: `DecodingError` describing what failed and where. An error
    ///   a custom `init(from:)` raised that was not a `DecodingError` is
    ///   reported as `dataCorrupted` with the original retained in
    ///   `underlyingError`.
    public func decode<T: Swift.Decodable>(
        _ type: T.Type = T.self
    ) throws(Swift.DecodingError) -> T {
        try JSON.Decoder(value: raw, codingPath: []).decoded(type)
    }
}
