/// JSON.Decode.swift
/// swift-json
///
/// JSON decoding namespace.
///
/// Houses the wholesale Span parser (``JSON/Decode/Implementation``)
/// and a public dispatcher (``JSON/Decode/parse(_:maxDepth:)``) that
/// routes arbitrary `Collection<UInt8>` / `String` / `Substring` inputs
/// through the Span fast path.
///
/// Renamed under Arc 1.6 namespace correction: implementation lives
/// under the `JSON.*` namespace, not at the L2 spec namespace.
///
/// ## Public surface
///
/// - ``JSON/Decode/parse(_:maxDepth:)-String`` — String → `RFC_8259.Value`
/// - ``JSON/Decode/parse(_:maxDepth:)-Substring`` — Substring → `RFC_8259.Value`
/// - ``JSON/Decode/parse(_:maxDepth:)-Collection`` — `Collection<UInt8>` → `RFC_8259.Value`
///
/// Consumers who want a `JSON` wrapper (instead of the bare
/// `RFC_8259.Value`) should call ``JSON/parse(_:)``. Consumers who
/// already hold a `Swift.Span<UInt8>` should use the
/// ``Coder_Primitives/Codable`` extension API:
/// `try RFC_8259.Value(decoding: &span)`.

public import RFC_8259

extension JSON {
    /// JSON decoding namespace. See file header.
    public enum Decode {}
}

// MARK: - Dispatcher: Collection<UInt8> → Value

extension JSON.Decode {
    /// Decodes a byte collection to a JSON value.
    ///
    /// Dispatches to the wholesale fast path when the collection
    /// exposes contiguous storage (the case for `[UInt8]` /
    /// `ContiguousArray<UInt8>` / `ArraySlice<UInt8>` etc.). Falls back
    /// to materialising to a contiguous `Array<UInt8>` and routing
    /// through the Span fast path for non-contiguous inputs.
    @inlinable
    public static func parse<C: Swift.Collection & Sendable>(
        _ bytes: C,
        maxDepth: Int = 512
    ) throws(RFC_8259.Error) -> RFC_8259.Value
    where C.Element == UInt8, C.Index: Sendable {
        var parserError: RFC_8259.Error? = nil
        let fastResult: RFC_8259.Value? = bytes.withContiguousStorageIfAvailable {
            (buffer: UnsafeBufferPointer<UInt8>) -> RFC_8259.Value? in
            let span = buffer.span
            do {
                return try Implementation.parse(span, maxDepth: maxDepth)
            } catch let error as RFC_8259.Error {
                parserError = error
                return nil
            } catch {
                parserError = nil
                return nil
            }
        } ?? nil
        if let value = fastResult { return value }
        if let err = parserError { throw err }
        let array = Swift.Array(bytes)
        return try array.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<UInt8>) throws(RFC_8259.Error) -> RFC_8259.Value in
            try Implementation.parse(buffer.span, maxDepth: maxDepth)
        }
    }
}

// MARK: - Dispatcher: String → Value

extension JSON.Decode {
    /// Decodes a JSON string to a JSON value.
    ///
    /// Dispatches to the wholesale fast path when the string's UTF-8
    /// view exposes contiguous storage (the case for native Swift
    /// `String` and — on Apple platforms with macOS 26 / iOS 26 — for
    /// bridged `NSString` per the A0 probe in
    /// `Experiments/parse-performance-tier-4-feasibility/`).
    @inlinable
    public static func parse(
        _ string: String,
        maxDepth: Int = 512
    ) throws(RFC_8259.Error) -> RFC_8259.Value {
        var parserError: RFC_8259.Error? = nil
        let fastResult: RFC_8259.Value? = string.utf8.withContiguousStorageIfAvailable {
            (buffer: UnsafeBufferPointer<UInt8>) -> RFC_8259.Value? in
            let span = buffer.span
            do {
                return try Implementation.parse(span, maxDepth: maxDepth)
            } catch let error as RFC_8259.Error {
                parserError = error
                return nil
            } catch {
                parserError = nil
                return nil
            }
        } ?? nil
        if let value = fastResult { return value }
        if let err = parserError { throw err }
        return try parse(Swift.Array(string.utf8), maxDepth: maxDepth)
    }
}

// MARK: - Dispatcher: Substring → Value

extension JSON.Decode {
    /// Decodes a JSON substring to a JSON value.
    @inlinable
    public static func parse(
        _ string: Substring,
        maxDepth: Int = 512
    ) throws(RFC_8259.Error) -> RFC_8259.Value {
        var parserError: RFC_8259.Error? = nil
        let fastResult: RFC_8259.Value? = string.utf8.withContiguousStorageIfAvailable {
            (buffer: UnsafeBufferPointer<UInt8>) -> RFC_8259.Value? in
            let span = buffer.span
            do {
                return try Implementation.parse(span, maxDepth: maxDepth)
            } catch let error as RFC_8259.Error {
                parserError = error
                return nil
            } catch {
                parserError = nil
                return nil
            }
        } ?? nil
        if let value = fastResult { return value }
        if let err = parserError { throw err }
        return try parse(Swift.Array(string.utf8), maxDepth: maxDepth)
    }
}
