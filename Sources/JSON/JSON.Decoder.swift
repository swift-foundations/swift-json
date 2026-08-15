/// JSON.Decoder.swift
/// swift-json
///
/// A Foundation-free `Swift.Decoder` driven by an already-parsed JSON value.
///
/// ## Why this exists alongside ``JSON/Serializable``
///
/// ``JSON/Serializable`` remains the preferred JSON attachment for any type
/// swift-json can reach: it is format-specific, carries no `associatedtype`,
/// and composes with the sibling format protocols (`Plist.Serializable`,
/// `XML.Serializable`, …) per the family-Codable convention.
///
/// It is unreachable for a type that must sit BELOW swift-json in the layer
/// graph. A Standards-layer (L2) type cannot conform to `JSON.Serializable`
/// without an upward L2 → L3 dependency on this package. `Swift.Decodable`
/// is the one decoding vocabulary such a type can adopt at no dependency
/// cost at all, because `Decodable`, `Decoder`, `CodingKey`, and
/// `DecodingError` are STANDARD LIBRARY declarations — not Foundation ones.
///
/// This decoder closes exactly that gap: the lower-layer type declares
/// `Decodable`, and this package supplies the `Decoder` that drives it from
/// a parsed JSON tree with no Foundation anywhere. `JSONDecoder` — the
/// Foundation spelling — stays confined to the `JSON Foundation
/// Integration` target.
///
/// ## Scope
///
/// Decoding only, from an already-parsed value. This type performs no
/// parsing (see ``JSON/parse(_:)-String``) and has no encoding counterpart.
///
/// ## Surface
///
/// The decoder and its three containers are deliberately `internal`. The
/// only public entry point is ``JSON/decode(_:)``; widening later is
/// additive, whereas a public surface committed now could not be narrowed.

import RFC_8259

extension JSON {
    /// A `Swift.Decoder` positioned at one node of a parsed JSON tree.
    ///
    /// Child decoders are produced by the containers, each carrying the
    /// coding path taken to reach it, so a failure deep in a nested
    /// structure reports the full ancestry.
    internal struct Decoder {
        /// The JSON value this decoder is positioned at.
        internal let value: RFC_8259.Value

        // swiftlint:disable no_any_protocol_existential - `codingPath` is declared `[any CodingKey]` by `Swift.Decoder`; the storage and the initializer that seeds it must spell the stdlib's element type (stdlib; rule-exemptions protocol-requirement shape)

        /// The path of coding keys taken to reach this point.
        internal let codingPath: [any CodingKey]

        // swiftlint:enable no_any_protocol_existential
    }
}

// MARK: - Swift.Decoder conformance

extension JSON.Decoder: Swift.Decoder {
    /// Always empty: this slice exposes no user-info channel.
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

    // swiftlint:disable:next no_any_protocol_existential - exact `UnkeyedDecodingContainer` requirement signature (stdlib; rule-exemptions protocol-requirement shape)
    internal func unkeyedContainer() throws(DecodingError) -> any UnkeyedDecodingContainer {
        guard case .array(let array) = value else {
            // swiftlint:disable:next no_any_protocol_existential - stdlib `UnkeyedDecodingContainer` existential metatype names the container the requirement returns (stdlib; rule-exemptions protocol-requirement shape)
            throw mismatch((any UnkeyedDecodingContainer).self)
        }
        return JSON.Decoder.Unkeyed(array: array, codingPath: codingPath)
    }

    // swiftlint:disable:next no_any_protocol_existential - exact `SingleValueDecodingContainer` requirement signature (stdlib; rule-exemptions protocol-requirement shape)
    internal func singleValueContainer() throws(DecodingError) -> any SingleValueDecodingContainer {
        JSON.Decoder.Single(decoder: self)
    }
}
