/// JSON.Span.EventStream.swift
/// swift-json
///
/// JSON-layer event cursor wrapping `RFC_8259.Span.EventStream`.
///
/// Phase A1 of the streaming-deserialize arc per
/// `swift-institute/Research/streaming-json-deserialize-comparative-analysis.md`
/// v1.0.1 §4.2. The JSON-layer wrapper translates `RFC_8259.Error`
/// into `JSON.Error` via the existing `JSON.Error.init(_: RFC_8259.Error)`
/// adapter — preserves the `JSON.Serializable` typed-throws contract
/// end-to-end through the streaming dispatch chain.
///
/// `~Copyable & ~Escapable` per the cursor lifetime contract;
/// `@_lifetime(borrow bytes)` at the initialiser; `@safe` per the
/// strict-memory-safety discipline. No `UnsafePointer<UInt8>`
/// introduced — backed by `Swift.Span<UInt8>` through the
/// inner `RFC_8259.Span.EventStream`.

import RFC_8259

extension JSON {
    /// Namespace for Span-backed JSON variants.
    ///
    /// Mirrors `RFC_8259.Span` one layer up — holds the public
    /// `EventStream` cursor that consumers may construct from
    /// `Swift.Span<UInt8>` to drive an event-grain decode.
    public enum Span {}
}

extension JSON.Span {
    /// Pull-driven event cursor over a contiguous-bytes JSON input.
    ///
    /// JSON-layer wrapper over `RFC_8259.Span.EventStream` that
    /// re-throws `RFC_8259.Error` as `JSON.Error`. Same API surface
    /// otherwise: `next()` / `currentString()` / `currentNumber()` /
    /// `skipValue()` / `isUnforkedAtPositionZero`.
    ///
    /// Token kinds are exposed via the `Token` typealias so
    /// JSON-side consumers don't need to import RFC 8259 directly to
    /// switch on them.
    ///
    /// `~Copyable & ~Escapable` per the cursor lifetime contract.
    // SAFETY: Safe by construction — composes only on top of safe
    // SAFETY: RFC_8259.Span.EventStream operations; @safe documents
    // SAFETY: that this type performs no unsafe operations.
    @safe
    public struct EventStream: ~Copyable, ~Escapable {
        @usableFromInline
        internal var inner: RFC_8259.Span.EventStream

        @inlinable
        @_lifetime(borrow bytes)
        public init(_ bytes: borrowing Swift.Span<UInt8>, maxDepth: Int = 512) {
            self.inner = RFC_8259.Span.EventStream(bytes, maxDepth: maxDepth)
        }
    }
}

// MARK: - Token typealias

extension JSON.Span.EventStream {
    /// Token kinds emitted by `next()`. Re-exports
    /// `RFC_8259.Token.Kind` verbatim — the kinds are JSON's, not
    /// RFC 8259's per se.
    public typealias Token = RFC_8259.Token.Kind
}

// MARK: - Short-circuit detection

extension JSON.Span.EventStream {
    /// Whether the stream is at the start of the input with no
    /// mutating calls yet made. Set by `init`, cleared by the first
    /// `next()` / `currentString()` / `currentNumber()` / `skipValue()`
    /// call. Used by `JSON.Assemble.from(_:)` to short-circuit to the
    /// existing tree path on the default-fallback per A0 §9.3.
    @inlinable
    public var isUnforkedAtPositionZero: Bool {
        inner.isUnforkedAtPositionZero
    }
}

// MARK: - Hot operations

extension JSON.Span.EventStream {
    /// Advances past whitespace and returns the next token kind.
    ///
    /// Returns `nil` at end of input. Throws `JSON.Error` on
    /// malformed inputs (translated from `RFC_8259.Error`).
    @inlinable
    @_lifetime(self: copy self)
    public mutating func next() throws(JSON.Error) -> Token? {
        do { return try inner.next() }
        catch { throw JSON.Error(error) }
    }

    /// Decodes the string at the current position. Call after
    /// `next()` returned `.string`.
    @inlinable
    @_lifetime(self: copy self)
    public mutating func currentString() throws(JSON.Error) -> String {
        do { return try inner.currentString() }
        catch { throw JSON.Error(error) }
    }

    /// Decodes the number at the current position. Call after
    /// `next()` returned `.number`.
    @inlinable
    @_lifetime(self: copy self)
    public mutating func currentNumber() throws(JSON.Error) -> RFC_8259.Number {
        do { return try inner.currentNumber() }
        catch { throw JSON.Error(error) }
    }

    /// Skips the value at the current position (structural skip via
    /// byte-walk; no allocations).
    @inlinable
    @_lifetime(self: copy self)
    public mutating func skipValue() throws(JSON.Error) {
        do { try inner.skipValue() }
        catch { throw JSON.Error(error) }
    }

    /// Lazy position for error reporting.
    @inlinable
    @_lifetime(self: copy self)
    public mutating func position() -> RFC_8259.Position {
        inner.position()
    }
}

// MARK: - Convenience expect helpers
//
// Embed the colon / object-start / array-start / array-end expectations
// in the surface so opt-in conformer bodies stay short. These are the
// ergonomics shape per §4.6's end-to-end example — they reduce the
// boilerplate at the conformer site to the minimum.

extension JSON.Span.EventStream {
    /// Asserts the next token is `.objectStart`; throws `JSON.Error`
    /// otherwise.
    @inlinable
    @_lifetime(self: copy self)
    public mutating func expectObjectStart() throws(JSON.Error) {
        guard let token = try next() else {
            throw .invalidSyntax(message: "expected '{', got end of input", location: position().location)
        }
        guard token == .objectStart else {
            throw .typeMismatch(expected: "object", got: token.description)
        }
    }

    /// Asserts the next token is `.arrayStart`; throws `JSON.Error`
    /// otherwise.
    @inlinable
    @_lifetime(self: copy self)
    public mutating func expectArrayStart() throws(JSON.Error) {
        guard let token = try next() else {
            throw .invalidSyntax(message: "expected '[', got end of input", location: position().location)
        }
        guard token == .arrayStart else {
            throw .typeMismatch(expected: "array", got: token.description)
        }
    }

    /// Asserts the next token is `.colon`; throws `JSON.Error`
    /// otherwise. Object decoders call this between key and value
    /// when the key was already consumed via `currentString()`.
    @inlinable
    @_lifetime(self: copy self)
    public mutating func expectColon() throws(JSON.Error) {
        guard let token = try next() else {
            throw .invalidSyntax(message: "expected ':', got end of input", location: position().location)
        }
        guard token == .colon else {
            throw .invalidSyntax(message: "expected ':', got \(token.description)", location: position().location)
        }
    }
}
