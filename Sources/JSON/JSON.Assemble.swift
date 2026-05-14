/// JSON.Assemble.swift
/// swift-json
///
/// Helper that assembles a `JSON` value from a
/// `JSON.Span.EventStream`. Used by the default fallback path on
/// `JSON.Serializable.deserialize(events:)`.
///
/// Phase A1 of the streaming-deserialize arc per
/// `swift-institute/Research/streaming-json-deserialize-comparative-analysis.md`
/// v1.0.1 §4.3.
///
/// ## Short-circuit (§4.3 mitigation 1 — REQUIRED per A0 §9.3)
///
/// When the input event stream is unforked at position 0 — i.e., the
/// consumer has not yet pulled any events — the helper delegates
/// directly to `RFC_8259.Span.Parser.parse(_:)` over the same byte
/// span. This collapses the default-fallback chain to the status-quo
/// tree path, eliminating the 4.48× silent-regression risk measured
/// in the A0 spike's `check-lifetime-inout-protocol` target.
///
/// The slow path (event-pull-and-rebuild) exists for completeness —
/// it handles the case where a future caller wraps a partial-decode
/// pattern in which events have already been consumed before
/// `JSON.Assemble.from(_:)` fires. The §4.3 default-fallback path
/// never exercises the slow path on existing conformers.

import RFC_8259

extension JSON {
    /// Helper namespace for assembling `JSON` values from event
    /// streams. Internal; called by the default `deserialize(events:)`
    /// implementation on `JSON.Serializable`.
    @usableFromInline
    internal enum Assemble {}
}

extension JSON.Assemble {
    /// Assembles a `JSON` value by consuming the event stream.
    ///
    /// FAST PATH: if `events.isUnforkedAtPositionZero` is `true`,
    /// delegate to `RFC_8259.Span.Parser.parse(_:)` over the same span
    /// — equivalent to status-quo `init(jsonBytes:)`. No event-pull,
    /// no tree-rebuild from events.
    ///
    /// SLOW PATH: events have been partially consumed; rebuild the
    /// `RFC_8259.Value` tree by driving the event stream forward.
    /// Used only by future callers wrapping partial-decode patterns —
    /// the §4.3 default-fallback shape exhibited by every existing
    /// conformer hits the FAST PATH.
    ///
    /// Per A0 §9.3, this short-circuit is the BINDING constraint
    /// that makes the §4.3 default-fallback non-regressing.
    @inlinable
    internal static func from(_ events: inout JSON.Span.EventStream) throws(JSON.Error) -> JSON {
        // FAST PATH: unforked at position 0 — delegate to Span.Parser.
        if events.isUnforkedAtPositionZero {
            do {
                let value = try events.inner.consumeAsParseValue()
                return JSON(value)
            } catch {
                throw JSON.Error(error)
            }
        }
        // SLOW PATH: events partially consumed. Build the tree by
        // driving the stream forward.
        return try buildFromEvents(&events)
    }

    /// Builds a `JSON` value by pulling events from the stream. Used
    /// by the slow path when the stream has been partially consumed.
    ///
    /// Drives `next()` and recurses on `.objectStart` / `.arrayStart`;
    /// reads payloads via `currentString()` / `currentNumber()`. The
    /// chain is equivalent to walking the event stream that a
    /// `RFC_8259.Span.Parser` parse would produce on the same input.
    @inlinable
    internal static func buildFromEvents(_ events: inout JSON.Span.EventStream) throws(JSON.Error) -> JSON {
        guard let token = try events.next() else {
            throw .emptyInput
        }
        return try buildValue(forToken: token, events: &events)
    }

    /// Builds a JSON value given the current token (already pulled
    /// from the stream).
    @inlinable
    internal static func buildValue(
        forToken token: RFC_8259.Token.Kind,
        events: inout JSON.Span.EventStream
    ) throws(JSON.Error) -> JSON {
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
            return JSON(.number(number))

        case .objectStart:
            return try buildObject(events: &events)

        case .arrayStart:
            return try buildArray(events: &events)

        case .objectEnd, .arrayEnd, .colon, .comma, .unknown(_):
            throw .invalidSyntax(
                message: "Unexpected token \(token.description) at start of value",
                location: events.position().location
            )
        }
    }

    /// Builds a JSON object (called after `.objectStart` consumed).
    @inlinable
    internal static func buildObject(events: inout JSON.Span.EventStream) throws(JSON.Error) -> JSON {
        var members: [(String, JSON)] = []
        // Empty object?
        guard let first = try events.next() else {
            throw .invalidSyntax(message: "Unexpected end of input in object", location: events.position().location)
        }
        if first == .objectEnd {
            return .object(members)
        }
        // First member: first should be .string for key.
        guard first == .string else {
            throw .invalidSyntax(message: "Expected object key (string), got \(first.description)", location: events.position().location)
        }
        let firstKey = try events.currentString()
        try events.expectColon()
        guard let firstValueToken = try events.next() else {
            throw .invalidSyntax(message: "Unexpected end of input in object value", location: events.position().location)
        }
        let firstValue = try buildValue(forToken: firstValueToken, events: &events)
        members.append((firstKey, firstValue))

        // Subsequent members.
        while true {
            guard let next = try events.next() else {
                throw .invalidSyntax(message: "Unexpected end of input in object", location: events.position().location)
            }
            switch next {
            case .objectEnd:
                return .object(members)
            case .comma:
                guard let keyToken = try events.next() else {
                    throw .invalidSyntax(message: "Unexpected end of input after ','", location: events.position().location)
                }
                guard keyToken == .string else {
                    throw .invalidSyntax(message: "Expected object key (string), got \(keyToken.description)", location: events.position().location)
                }
                let key = try events.currentString()
                try events.expectColon()
                guard let valueToken = try events.next() else {
                    throw .invalidSyntax(message: "Unexpected end of input after ':'", location: events.position().location)
                }
                let value = try buildValue(forToken: valueToken, events: &events)
                members.append((key, value))
            default:
                throw .invalidSyntax(message: "Expected ',' or '}', got \(next.description)", location: events.position().location)
            }
        }
    }

    /// Builds a JSON array (called after `.arrayStart` consumed).
    @inlinable
    internal static func buildArray(events: inout JSON.Span.EventStream) throws(JSON.Error) -> JSON {
        var elements: [JSON] = []
        guard let first = try events.next() else {
            throw .invalidSyntax(message: "Unexpected end of input in array", location: events.position().location)
        }
        if first == .arrayEnd {
            return .array(elements)
        }
        let firstValue = try buildValue(forToken: first, events: &events)
        elements.append(firstValue)

        while true {
            guard let next = try events.next() else {
                throw .invalidSyntax(message: "Unexpected end of input in array", location: events.position().location)
            }
            switch next {
            case .arrayEnd:
                return .array(elements)
            case .comma:
                guard let valueToken = try events.next() else {
                    throw .invalidSyntax(message: "Unexpected end of input after ','", location: events.position().location)
                }
                let value = try buildValue(forToken: valueToken, events: &events)
                elements.append(value)
            default:
                throw .invalidSyntax(message: "Expected ',' or ']', got \(next.description)", location: events.position().location)
            }
        }
    }
}
