/// JSON.Span.EventStream.swift
/// swift-json
///
/// JSON-layer event cursor — thin error-conversion wrapper over the
/// direct ``Lexer/Pull/Stream`` specialised to ``RFC_8259/Pull/Tokens``.
///
/// The wrapper exists for one reason only: ``JSON/Serializable``'s
/// public protocol declares `throws(JSON.Error)`, while the underlying
/// L1 stream throws ``RFC_8259/Error``. The wrapper converts at the
/// boundary. The case-(c) pull-down of the structural-event machinery
/// to L1 (per the 2026-05-14 [RES-018] amendment) is complete on the
/// L2 side — the deleted `RFC_8259.Span.EventStream` was the
/// preserve-the-RFC_8259-API wrapper; this is a different category
/// (typed-throws conversion).

import RFC_8259

extension JSON {
    /// Namespace for Span-backed JSON variants.
    public enum Span {}
}

extension JSON.Span {
    /// Pull-driven event cursor over a contiguous-bytes JSON input.
    ///
    /// Wraps `Lexer.Pull.Stream<RFC_8259.Pull.Tokens>` directly. Re-throws
    /// `RFC_8259.Error` as `JSON.Error` so `JSON.Serializable` consumers
    /// continue to see a single typed-throws error contract.
    @safe
    public struct EventStream: ~Copyable, ~Escapable {
        @usableFromInline
        internal var inner: Lexer.Pull.Stream<RFC_8259.Pull.Tokens>

        @inlinable
        @_lifetime(borrow bytes)
        public init(_ bytes: borrowing Swift.Span<Byte>, maxDepth: Int = 512) {
            self.inner = Lexer.Pull.Stream<RFC_8259.Pull.Tokens>(bytes, limit: maxDepth)
        }
    }
}

// MARK: - Token typealias

extension JSON.Span.EventStream {
    /// Token kinds emitted by `next()`.
    public typealias Token = RFC_8259.Token.Kind
}

// MARK: - Short-circuit detection

extension JSON.Span.EventStream {
    /// `true` until the first mutating call advances the cursor.
    ///
    /// Used by `JSON.Assemble.from(_:)` to short-circuit to the
    /// wholesale-parse fast path on the default fallback.
    @inlinable
    public var isUnforkedAtPositionZero: Bool {
        inner.isPristine
    }
}

// MARK: - Hot operations

extension JSON.Span.EventStream {
    @inlinable
    @_lifetime(self: copy self)
    public mutating func next() throws(JSON.Error) -> Token? {
        do throws(RFC_8259.Error) { return try inner.next() } catch { throw JSON.Error(error) }
    }

    @inlinable
    @_lifetime(self: copy self)
    public mutating func currentString() throws(JSON.Error) -> String {
        do throws(RFC_8259.Error) { return try inner.currentString() } catch { throw JSON.Error(error) }
    }

    @inlinable
    @_lifetime(self: copy self)
    public mutating func currentNumber() throws(JSON.Error) -> RFC_8259.Number {
        do throws(RFC_8259.Error) { return try inner.currentNumber() } catch { throw JSON.Error(error) }
    }

    @inlinable
    @_lifetime(self: copy self)
    public mutating func skipValue() throws(JSON.Error) {
        do throws(RFC_8259.Error) { try inner.skip() } catch { throw JSON.Error(error) }
    }

    @inlinable
    public func position() -> RFC_8259.Position {
        inner.position(at: inner.position)
    }

    @inlinable
    @_lifetime(self: copy self)
    public mutating func peekStructural() -> UInt8? {
        inner.peek().map(\.underlying)
    }
}

// MARK: - Convenience expect helpers

extension JSON.Span.EventStream {
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
