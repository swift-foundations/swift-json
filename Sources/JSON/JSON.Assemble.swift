/// JSON.Assemble.swift
/// swift-json
///
/// JSON assemble strategy for the L1 ``Lexer/Pull/Assemble`` cohort.
///
/// Implements ``Lexer/Pull/Assemble/Strategy`` for RFC 8259 JSON.
/// Supplies:
///
/// - `Tokens` = ``RFC_8259/Pull/Tokens`` (the JSON token witness at L2).
/// - `Value` = ``RFC_8259/Value`` (the JSON value tree at L2).
/// - `consume(bytes:limit:)` — the wholesale fast-path. After the
///   Decode-relocation commit, delegates to the moved
///   ``RFC_8259/Decode/Implementation/parse(_:maxDepth:)``-equivalent
///   at L3. Until then, falls back to event-walking via `build`.
/// - `build(events:)` — the slow-path. Walks the event stream and
///   builds ``RFC_8259/Value`` event-by-event.
///
/// Relocated from swift-rfc-8259's `RFC_8259.Pull.Assemble` (Arc 1.5):
/// the Strategy conformance is implementation, not spec, so it lives
/// at L3. The L1 ``Lexer/Pull/Assemble/from(_:strategy:)`` utility
/// remains at L1; this type is an internal strategy passed to it.

public import RFC_8259

extension JSON {
    /// JSON assemble strategy. Internal — surfaced only as an
    /// implementation detail to compose with ``Lexer/Pull/Assemble``.
    @usableFromInline
    internal enum Assemble {}
}

// MARK: - Strategy conformance

extension JSON.Assemble: Lexer.Pull.Assemble.Strategy {
    @usableFromInline
    internal typealias Tokens = RFC_8259.Pull.Tokens

    @usableFromInline
    internal typealias Value = RFC_8259.Value

    /// Wholesale fast-path — delegates to ``RFC_8259/Decode/Implementation/parse(_:maxDepth:)``.
    ///
    /// Per A0 §9.3, this short-circuit is the BINDING constraint that
    /// makes the §4.3 default-fallback non-regressing.
    @inlinable
    internal static func consume(
        bytes: Swift.Span<UInt8>,
        limit: Int
    ) throws(RFC_8259.Error) -> RFC_8259.Value {
        try JSON.Decode.Implementation.parse(bytes, maxDepth: limit)
    }

    /// Slow-path — drives the event stream to rebuild the tree.
    @inlinable
    internal static func build(
        events: inout Lexer.Pull.Stream<RFC_8259.Pull.Tokens>
    ) throws(RFC_8259.Error) -> RFC_8259.Value {
        guard let token = try events.next() else {
            throw .unexpectedEndOfInput(
                at: events.position(at: events.position),
                expected: .value
            )
        }
        return try buildValue(forToken: token, events: &events)
    }

    @inlinable
    internal static func buildValue(
        forToken token: RFC_8259.Token.Kind,
        events: inout Lexer.Pull.Stream<RFC_8259.Pull.Tokens>
    ) throws(RFC_8259.Error) -> RFC_8259.Value {
        switch token {
        case .null:
            return .null
        case .`true`:
            return .bool(true)
        case .`false`:
            return .bool(false)
        case .string:
            let value = try events.currentString()
            return .string(value)
        case .number:
            let number = try events.currentNumber()
            return .number(number)
        case .objectStart:
            return try buildObject(events: &events)
        case .arrayStart:
            return try buildArray(events: &events)
        case .objectEnd, .arrayEnd, .colon, .comma, .unknown(_):
            throw .unexpectedToken(
                at: events.position(at: events.position),
                found: token,
                expected: .value
            )
        }
    }

    @inlinable
    internal static func buildObject(
        events: inout Lexer.Pull.Stream<RFC_8259.Pull.Tokens>
    ) throws(RFC_8259.Error) -> RFC_8259.Value {
        var members: [(key: String, value: RFC_8259.Value)] = []
        guard let first = try events.next() else {
            throw .unexpectedEndOfInput(at: events.position(at: events.position), expected: .objectEnd)
        }
        if first == .objectEnd {
            return .object(RFC_8259.Object(members))
        }
        guard first == .string else {
            throw .unexpectedToken(
                at: events.position(at: events.position),
                found: first,
                expected: .objectKey
            )
        }
        let firstKey = try events.currentString()
        try expectColon(&events)
        guard let firstValueToken = try events.next() else {
            throw .unexpectedEndOfInput(at: events.position(at: events.position), expected: .value)
        }
        let firstValue = try buildValue(forToken: firstValueToken, events: &events)
        members.append((key: firstKey, value: firstValue))

        while true {
            guard let next = try events.next() else {
                throw .unexpectedEndOfInput(at: events.position(at: events.position), expected: .objectEnd)
            }
            switch next {
            case .objectEnd:
                return .object(RFC_8259.Object(members))
            case .comma:
                guard let keyToken = try events.next() else {
                    throw .unexpectedEndOfInput(at: events.position(at: events.position), expected: .objectKey)
                }
                guard keyToken == .string else {
                    throw .unexpectedToken(
                        at: events.position(at: events.position),
                        found: keyToken,
                        expected: .objectKey
                    )
                }
                let key = try events.currentString()
                try expectColon(&events)
                guard let valueToken = try events.next() else {
                    throw .unexpectedEndOfInput(at: events.position(at: events.position), expected: .value)
                }
                let value = try buildValue(forToken: valueToken, events: &events)
                members.append((key: key, value: value))
            default:
                throw .unexpectedToken(
                    at: events.position(at: events.position),
                    found: next,
                    expected: .commaOrEnd
                )
            }
        }
    }

    @inlinable
    internal static func buildArray(
        events: inout Lexer.Pull.Stream<RFC_8259.Pull.Tokens>
    ) throws(RFC_8259.Error) -> RFC_8259.Value {
        var elements: [RFC_8259.Value] = []
        guard let first = try events.next() else {
            throw .unexpectedEndOfInput(at: events.position(at: events.position), expected: .arrayEnd)
        }
        if first == .arrayEnd {
            return .array(RFC_8259.Array(elements))
        }
        let firstValue = try buildValue(forToken: first, events: &events)
        elements.append(firstValue)

        while true {
            guard let next = try events.next() else {
                throw .unexpectedEndOfInput(at: events.position(at: events.position), expected: .arrayEnd)
            }
            switch next {
            case .arrayEnd:
                return .array(RFC_8259.Array(elements))
            case .comma:
                guard let valueToken = try events.next() else {
                    throw .unexpectedEndOfInput(at: events.position(at: events.position), expected: .value)
                }
                let value = try buildValue(forToken: valueToken, events: &events)
                elements.append(value)
            default:
                throw .unexpectedToken(
                    at: events.position(at: events.position),
                    found: next,
                    expected: .commaOrEnd
                )
            }
        }
    }

    @inlinable
    internal static func expectColon(
        _ events: inout Lexer.Pull.Stream<RFC_8259.Pull.Tokens>
    ) throws(RFC_8259.Error) {
        guard let token = try events.next() else {
            throw .unexpectedEndOfInput(at: events.position(at: events.position), expected: .colon)
        }
        guard token == .colon else {
            throw .unexpectedToken(
                at: events.position(at: events.position),
                found: token,
                expected: .colon
            )
        }
    }
}

// MARK: - JSON.Error-adapter helper

extension JSON.Assemble {
    /// Assembles a `JSON` value by delegating to
    /// ``Lexer/Pull/Assemble/from(_:strategy:)`` with this strategy and
    /// adapting `RFC_8259.Error` → `JSON.Error`.
    ///
    /// Preserves the call-site contract at
    /// `JSON.Serializable.deserialize(events:)`.
    @inlinable
    internal static func from(_ events: inout JSON.Span.EventStream) throws(JSON.Error) -> JSON {
        do throws(RFC_8259.Error) {
            let value = try Lexer.Pull.Assemble.from(&events.inner, strategy: JSON.Assemble.self)
            return JSON(value)
        } catch {
            throw JSON.Error(error)
        }
    }
}
