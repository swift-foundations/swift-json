/// JSON.Decoder.Key.swift
/// swift-json
///
/// The decoder's own ``Swift/CodingKey``.
///
/// Used wherever the decoder must name a position the caller supplied no
/// key for: array indices (where `intValue` carries the index) and the
/// `super` slot. Keys the CALLER supplies are never replaced by this type
/// — they are appended to the coding path as-is, so a caller's custom key
/// keeps both its `stringValue` and its `intValue`.

extension JSON.Decoder {
    /// A coding key naming a position the caller supplied no key for.
    internal struct Key {
        /// The string form — an object member name, or an index rendered
        /// in base 10.
        internal let stringValue: String

        /// The integer form, present for array indices and absent for
        /// object member names.
        internal let intValue: Int?
    }
}

// MARK: - CodingKey conformance

extension JSON.Decoder.Key: CodingKey {
    /// Never fails: every string names a possible JSON object member.
    internal init?(stringValue: String) {
        self.init(stringValue: stringValue, intValue: nil)
    }

    /// Never fails: retains the integer form alongside its base-10 spelling.
    internal init?(intValue: Int) {
        self.init(stringValue: "\(intValue)", intValue: intValue)
    }
}

// MARK: - Well-known keys

extension JSON.Decoder.Key {
    /// The member name a keyed container's `superDecoder()` reads.
    internal static let `super` = JSON.Decoder.Key(
        stringValue: "super",
        intValue: nil
    )

    /// The key naming array position `index`.
    internal static func index(_ index: Int) -> JSON.Decoder.Key {
        JSON.Decoder.Key(stringValue: "\(index)", intValue: index)
    }
}
