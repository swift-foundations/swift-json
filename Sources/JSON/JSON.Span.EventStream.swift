import RFC_8259

extension JSON {

    public enum Span {}
}

extension JSON.Span {

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

extension JSON.Span.EventStream {

    public typealias Token = RFC_8259.Token.Kind
}

extension JSON.Span.EventStream {

    @inlinable
    public var isUnforkedAtPositionZero: Bool {
        inner.isPristine
    }
}

extension JSON.Span.EventStream {
    @inlinable
    @_lifetime(self: copy self)
    public mutating func next() throws(JSON.Error) -> Token? {
        do throws(RFC_8259.Error) { return try inner.next() } catch { throw JSON.Error(error) }
    }

    @inlinable
    @_lifetime(self: copy self)
    public mutating func currentString() throws(JSON.Error) -> String {
        do throws(RFC_8259.Error) { return try inner.currentString() } catch {
            throw JSON.Error(error)
        }
    }

    @inlinable
    @_lifetime(self: copy self)
    public mutating func currentNumber() throws(JSON.Error) -> RFC_8259.Number {
        do throws(RFC_8259.Error) { return try inner.currentNumber() } catch {
            throw JSON.Error(error)
        }
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

extension JSON.Span.EventStream {
    @inlinable
    @_lifetime(self: copy self)
    public mutating func expectObjectStart() throws(JSON.Error) {
        guard let token = try next() else {
            throw .invalidSyntax(
                message: "expected '{', got end of input",
                location: position().location
            )
        }
        guard token == .objectStart else {
            throw .typeMismatch(expected: "object", got: token.description)
        }
    }

    @inlinable
    @_lifetime(self: copy self)
    public mutating func expectArrayStart() throws(JSON.Error) {
        guard let token = try next() else {
            throw .invalidSyntax(
                message: "expected '[', got end of input",
                location: position().location
            )
        }
        guard token == .arrayStart else {
            throw .typeMismatch(expected: "array", got: token.description)
        }
    }

    @inlinable
    @_lifetime(self: copy self)
    public mutating func expectColon() throws(JSON.Error) {
        guard let token = try next() else {
            throw .invalidSyntax(
                message: "expected ':', got end of input",
                location: position().location
            )
        }
        guard token == .colon else {
            throw .invalidSyntax(
                message: "expected ':', got \(token.description)",
                location: position().location
            )
        }
    }
}
