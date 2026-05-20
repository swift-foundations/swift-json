/// JSON.Encode.swift
/// swift-json
///
/// JSON encoding namespace.
///
/// Houses the internal encoder state (``JSON/Encode/Encoder``),
/// public encoding options (``JSON/Encode/Options``), and the
/// internal size estimator (``JSON/Encode/Size``).
///
/// Renamed under Arc 1.6 namespace correction: encoding implementation
/// lives under the `JSON.*` namespace, not at the L2 spec namespace.
///
/// ## Public surface
///
/// Consumers SHOULD encode via the ``Coder_Primitives/Codable``
/// extension API:
///
/// ```swift
/// let bytes: [UInt8] = try value.encoded()
/// ```
///
/// Or via a ``JSON/Coder`` with non-default options:
///
/// ```swift
/// let coder = JSON.Coder(encodeOptions: JSON.Encode.Options(prettyPrint: true))
/// var bytes: [UInt8] = []
/// try coder.serialize(value, into: &bytes)
/// ```

public import RFC_8259

extension JSON {
    /// JSON encoding namespace. See file header.
    public enum Encode {}
}

// MARK: - Encode Error

extension JSON.Encode {
    /// An error thrown by the JSON encoder.
    ///
    /// The thrown form of the encoder's ``Coder_Primitives/Coder/Protocol``
    /// conformance (``JSON/Coder``). The non-throwing convenience entry
    /// points (``encode(_:options:)`` and ``encode(_:into:options:)``)
    /// preserve their non-throwing contract by treating depth overflow
    /// as a precondition-equivalent fault via `try!`.
    public enum Error: Swift.Error, Sendable, Hashable {
        /// Encoding exceeded the configured maximum nesting depth.
        case depthExceeded(maxDepth: Int)
    }
}

extension JSON.Encode.Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .depthExceeded(let maxDepth):
            return "JSON encoding exceeded maximum depth of \(maxDepth)"
        }
    }
}

// MARK: - Convenience encode entry points

extension JSON.Encode {
    /// Encodes a JSON value to UTF-8 bytes.
    ///
    /// Convenience entry point that materialises the encoded bytes
    /// into a fresh `[UInt8]`. For appending into an existing buffer
    /// use ``encode(_:into:options:)``.
    ///
    /// Depth overflow is treated as a precondition-equivalent fault
    /// at this entry point; consumers needing typed propagation should
    /// use ``JSON/Coder`` (which throws ``JSON/Encode/Error``).
    @inlinable
    public static func encode(
        _ value: RFC_8259.Value,
        options: JSON.Encode.Options = JSON.Encode.Options()
    ) -> [UInt8] {
        var buffer: [UInt8] = []
        var encoder = Encoder(options: options)
        try! encoder.encode(value, into: &buffer)
        return buffer
    }

    /// Encodes a JSON value, appending to an existing buffer.
    ///
    /// Depth overflow is treated as a precondition-equivalent fault
    /// at this entry point; consumers needing typed propagation should
    /// use ``JSON/Coder`` (which throws ``JSON/Encode/Error``).
    @inlinable
    public static func encode<Buffer: Swift.RangeReplaceableCollection>(
        _ value: RFC_8259.Value,
        into buffer: inout Buffer,
        options: JSON.Encode.Options = JSON.Encode.Options()
    ) where Buffer.Element == UInt8 {
        var encoder = Encoder(options: options)
        try! encoder.encode(value, into: &buffer)
    }
}
