/// RFC_8259.Encode.swift
/// swift-json
///
/// JSON encoding (Value → bytes).
///
/// Relocated to swift-json (L3) under Arc 1.5 — encoding is
/// implementation, not RFC 8259 spec. The `RFC_8259.Encode` struct
/// is declared here as an extension on `RFC_8259` from L3; consumers
/// importing JSON see it via JSON's re-export of RFC_8259.

public import RFC_8259
public import Binary_Primitives

extension RFC_8259 {
    /// Encodes a JSON value to UTF-8 bytes.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let value: RFC_8259.Value = ["name": "John", "age": 30]
    ///
    /// // Compact encoding
    /// let bytes = value.encode()
    ///
    /// // Pretty-printed
    /// let pretty = value.encode(options: .init(prettyPrint: true))
    ///
    /// // Encode into existing buffer
    /// var buffer: [UInt8] = []
    /// value.encode(into: &buffer)
    /// ```
    public struct Encode: Sendable {
        /// The value to encode.
        public let value: Value

        @usableFromInline
        internal init(_ value: Value) {
            self.value = value
        }
    }
}

// MARK: - Encode callAsFunction

extension RFC_8259.Encode {
    /// Encodes the value to a byte array.
    ///
    /// - Parameter options: Encoding options.
    /// - Returns: UTF-8 encoded JSON bytes.
    @inlinable
    public func callAsFunction(options: Options = Options()) -> [UInt8] {
        var buffer: [UInt8] = []
        buffer.reserveCapacity(size())
        callAsFunction(into: &buffer, options: options)
        return buffer
    }

    /// Encodes the value into an existing buffer.
    ///
    /// - Parameters:
    ///   - buffer: The buffer to append to.
    ///   - options: Encoding options.
    @inlinable
    public func callAsFunction<Buffer: Swift.RangeReplaceableCollection>(
        into buffer: inout Buffer,
        options: Options = Options()
    ) where Buffer.Element == UInt8 {
        var encoder = Encoder(options: options)
        encoder.encode(value, into: &buffer)
    }

    /// Accessor for size estimation.
    public var size: Size { Size(value) }
}

// MARK: - Value.encode Extension

extension RFC_8259.Value {
    /// Creates an encoder for this value.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let bytes = value.encode()
    /// let pretty = value.encode(options: .init(prettyPrint: true))
    /// ```
    public var encode: RFC_8259.Encode {
        RFC_8259.Encode(self)
    }
}

// MARK: - Binary.Serializable Conformance

extension RFC_8259.Value: @retroactive Binary.Serializable {
    /// Serializes a JSON value to UTF-8 bytes.
    ///
    /// Uses compact encoding (no pretty-printing, no sorted keys).
    /// For custom formatting, use `value.encode(options:)` instead.
    ///
    /// - Parameters:
    ///   - value: The JSON value to serialize.
    ///   - buffer: The buffer to append bytes to.
    @inlinable
    public static func serialize<Buffer: Swift.RangeReplaceableCollection>(
        _ value: Self,
        into buffer: inout Buffer
    ) where Buffer.Element == UInt8 {
        var encoder = RFC_8259.Encode.Encoder(options: RFC_8259.Encode.Options())
        encoder.encode(value, into: &buffer)
    }
}
