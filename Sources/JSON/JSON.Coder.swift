/// JSON.Coder.swift
/// swift-json
///
/// The canonical bidirectional codec for RFC 8259 JSON.
///
/// Implements ``Coder_Primitives/Coder/Protocol`` for `RFC_8259.Value`:
/// decode parses a `Swift.Span<UInt8>` to a value via the wholesale
/// Span parser; encode serialises a value into a `[UInt8]` buffer via
/// the JSON encoder.
///
/// Per the swift-coder-primitives framing memo
/// (`project_parser_serializer_coder_system_framing`), Coder is a
/// leaf type with no `Body`/`Builder` — one Coder per format×value
/// pair. JSON has one canonical Coder: this type.
///
/// ## Consumers
///
/// `RFC_8259.Value` conforms to ``Coder_Primitives/Codable`` (the
/// canonical-coder attachment protocol) at the bottom of this file,
/// so consumers may write:
///
/// ```swift
/// var input: Swift.Span<UInt8> = …
/// let value = try RFC_8259.Value(decoding: &input)
/// let bytes: [UInt8] = try value.encoded()
/// ```

public import Coder_Primitives
public import RFC_8259

extension JSON {
    /// The canonical bidirectional codec for RFC 8259 JSON.
    ///
    /// Conforms to ``Coder_Primitives/Coder/Protocol`` with:
    ///
    /// - `DecodeInput` = `Swift.Span<UInt8>` (contiguous bytes; the
    ///   public API at swift-json materialises arbitrary inputs to
    ///   contiguous storage before constructing the span).
    /// - `EncodeBuffer` = `[UInt8]`.
    /// - `Output` = ``RFC_8259/Value``.
    /// - `DecodeFailure` = ``RFC_8259/Error``.
    /// - `EncodeFailure` = `Never` (encoding a well-typed value
    ///   cannot fail; depth overflow is a precondition failure, not
    ///   a thrown error, per ``RFC_8259/Encode/Options``).
    public struct Coder: Sendable {
        /// Maximum nesting depth (default 512).
        public let maxDepth: Int

        /// Encoding options (default compact, no slash escaping).
        public let encodeOptions: JSON.Encode.Options

        @inlinable
        public init(
            maxDepth: Int = 512,
            encodeOptions: JSON.Encode.Options = JSON.Encode.Options()
        ) {
            self.maxDepth = maxDepth
            self.encodeOptions = encodeOptions
        }
    }
}

// MARK: - Coder.Protocol conformance

extension JSON.Coder: Coder_Primitives.Coder.`Protocol` {
    public typealias DecodeInput = Swift.Span<UInt8>
    public typealias EncodeBuffer = [UInt8]
    public typealias Output = RFC_8259.Value
    public typealias DecodeFailure = RFC_8259.Error
    public typealias EncodeFailure = Never

    /// Decodes a JSON value from a contiguous byte span.
    ///
    /// The wholesale Span parser consumes the entire input
    /// (trailing-content check per RFC 8259 §2). On success the
    /// entire input has been consumed; `input` is left unchanged
    /// since this format does not support partial decoding.
    @inlinable
    public func decode(
        _ input: inout Swift.Span<UInt8>
    ) throws(RFC_8259.Error) -> RFC_8259.Value {
        try JSON.Decode.Implementation.parse(input, maxDepth: maxDepth)
    }

    /// Encodes a JSON value by appending to a UTF-8 byte buffer.
    @inlinable
    public func encode(
        _ output: RFC_8259.Value,
        into buffer: inout [UInt8]
    ) {
        var encoder = JSON.Encode.Encoder(options: encodeOptions)
        encoder.encode(output, into: &buffer)
    }
}

// MARK: - Codable attachment on RFC_8259.Value

extension RFC_8259.Value: @retroactive Coder_Primitives.Codable {
    public typealias Coder = JSON.Coder

    /// The canonical bidirectional codec for `RFC_8259.Value`.
    @inlinable
    public static var coder: JSON.Coder { JSON.Coder() }
}
