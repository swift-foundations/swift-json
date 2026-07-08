/// JSON.Coder.swift
/// swift-json
///
/// The canonical bidirectional codec for RFC 8259 JSON.
///
/// Implements ``Coder_Primitives/Coder/Protocol`` for `RFC_8259.Value`:
/// `parse` consumes a `Swift.Span<UInt8>` via the wholesale Span
/// parser; `serialize` appends bytes to a `[UInt8]` buffer via the
/// JSON encoder. Per [FAM-006], `Coder.Protocol` refines
/// `Parser.Protocol + Serializer.Protocol`; this conformance picks up
/// the inherited `Input` / `Buffer` / `Output` / `Failure` typealiases
/// via same-name unification.
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
public import Either_Primitives
public import RFC_8259

extension JSON {
    /// The canonical bidirectional codec for RFC 8259 JSON.
    ///
    /// Conforms to ``Coder_Primitives/Coder/Protocol`` with:
    ///
    /// - `Input`   = `Swift.Span<UInt8>` (contiguous bytes; the
    ///   public API at swift-json materialises arbitrary inputs to
    ///   contiguous storage before constructing the span).
    /// - `Buffer`  = `[UInt8]`.
    /// - `Output`  = ``RFC_8259/Value``.
    /// - `Failure` = `Either<RFC_8259.Error, JSON.Encode.Error>`. Decode
    ///   surfaces ``RFC_8259/Error`` as `.left`; encode surfaces
    ///   ``JSON/Encode/Error`` as `.right`. The non-throwing convenience
    ///   entry points (``JSON/Encode/encode(_:options:)`` and
    ///   ``JSON/Encode/encode(_:into:options:)``) preserve their
    ///   non-throwing contract via `try!`.
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
    public typealias Input = Swift.Span<Byte>
    public typealias Buffer = [UInt8]
    public typealias Output = RFC_8259.Value
    public typealias Failure = Either<RFC_8259.Error, JSON.Encode.Error>

    /// Parses a JSON value from a contiguous byte span.
    ///
    /// The wholesale Span parser consumes the entire input
    /// (trailing-content check per RFC 8259 §2). On success,
    /// `input` is advanced to an empty span at the end (entire
    /// input was consumed), honoring the
    /// ``Coder_Primitives/Coder/Protocol`` inout-advance contract.
    ///
    /// Decode-side faults surface as `.left(RFC_8259.Error)` in
    /// the unified `Failure` type.
    @inlinable
    public func parse(
        _ input: inout Swift.Span<Byte>
    ) throws(Failure) -> RFC_8259.Value {
        let value: RFC_8259.Value
        do throws(RFC_8259.Error) {
            value = try JSON.Decode.Implementation.parse(input, maxDepth: maxDepth)
        } catch {
            throw .left(error)
        }
        // Advance input to an empty span at the end: the wholesale
        // parser consumed the entire input on success (per RFC 8259
        // §2 trailing-content check).
        input = input.extracting(input.count..<input.count)
        return value
    }

    /// Serializes a JSON value by appending to a UTF-8 byte buffer.
    ///
    /// Throws ``JSON/Encode/Error/depthExceeded(maxDepth:)`` (surfaced
    /// as `.right(JSON.Encode.Error)` in the unified `Failure` type)
    /// when nesting exceeds ``JSON/Encode/Options/maxDepth``.
    @inlinable
    public func serialize(
        _ output: RFC_8259.Value,
        into buffer: inout [UInt8]
    ) throws(Failure) {
        var encoder = JSON.Encode.Encoder(options: encodeOptions)
        do throws(JSON.Encode.Error) {
            try encoder.encode(output, into: &buffer)
        } catch {
            throw .right(error)
        }
    }
}

// MARK: - Codable attachment on RFC_8259.Value

extension RFC_8259.Value: @retroactive Coder_Primitives.Codable {
    /// CANONICAL-ATTACHMENT JUSTIFICATION [FAM-003]:
    /// `RFC_8259.Value` has exactly one inherent canonical codec — JSON.
    /// The associatedtype commitment to `JSON.Coder` is structurally
    /// correct because `RFC_8259.Value` cannot meaningfully be encoded
    /// as anything other than its JSON representation; it IS the JSON
    /// tree value type. Format-specific siblings (`JSON.Serializable`,
    /// `Binary.Serializable`, etc.) are reserved for types whose
    /// representation is format-dependent and have no single inherent
    /// canonical codec.
    public typealias Coder = JSON.Coder

    /// The canonical bidirectional codec for `RFC_8259.Value`.
    @inlinable
    public static var coder: JSON.Coder { JSON.Coder() }
}
