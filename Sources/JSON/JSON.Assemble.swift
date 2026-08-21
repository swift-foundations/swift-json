public import RFC_8259

extension JSON {

    @usableFromInline
    internal enum Assemble {}
}

extension JSON.Assemble: Lexer.Pull.Assemble.Strategy {
    @usableFromInline
    internal typealias Tokens = RFC_8259.Pull.Tokens

    @usableFromInline
    internal typealias Value = RFC_8259.Value

    @inlinable
    package static func consume(
        bytes: Swift.Span<Byte>,
        limit: Int
    ) throws(RFC_8259.Error) -> RFC_8259.Value {
        try JSON.Decode.Implementation.parse(bytes, maxDepth: limit)
    }

    @inlinable
    package static func build(
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
    package static func buildValue(
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

        case .objectEnd, .arrayEnd, .colon, .comma, .unknown:
            throw .unexpectedToken(
                at: events.position(at: events.position),
                found: token,
                expected: .value
            )
        }
    }

    @inlinable
    package static func buildObject(
        events: inout Lexer.Pull.Stream<RFC_8259.Pull.Tokens>
    ) throws(RFC_8259.Error) -> RFC_8259.Value {
        var members: [(key: String, value: RFC_8259.Value)] = []
        guard let first = try events.next() else {
            throw .unexpectedEndOfInput(
                at: events.position(at: events.position),
                expected: .objectEnd
            )
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
                throw .unexpectedEndOfInput(
                    at: events.position(at: events.position),
                    expected: .objectEnd
                )
            }
            switch next {
            case .objectEnd:
                return .object(RFC_8259.Object(members))

            case .comma:
                guard let keyToken = try events.next() else {
                    throw .unexpectedEndOfInput(
                        at: events.position(at: events.position),
                        expected: .objectKey
                    )
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
                    throw .unexpectedEndOfInput(
                        at: events.position(at: events.position),
                        expected: .value
                    )
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
    package static func buildArray(
        events: inout Lexer.Pull.Stream<RFC_8259.Pull.Tokens>
    ) throws(RFC_8259.Error) -> RFC_8259.Value {
        var elements: [RFC_8259.Value] = []
        guard let first = try events.next() else {
            throw .unexpectedEndOfInput(
                at: events.position(at: events.position),
                expected: .arrayEnd
            )
        }
        if first == .arrayEnd {
            return .array(RFC_8259.Array(elements))
        }
        let firstValue = try buildValue(forToken: first, events: &events)
        elements.append(firstValue)

        while true {
            guard let next = try events.next() else {
                throw .unexpectedEndOfInput(
                    at: events.position(at: events.position),
                    expected: .arrayEnd
                )
            }
            switch next {
            case .arrayEnd:
                return .array(RFC_8259.Array(elements))

            case .comma:
                guard let valueToken = try events.next() else {
                    throw .unexpectedEndOfInput(
                        at: events.position(at: events.position),
                        expected: .value
                    )
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
    package static func expectColon(
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

extension JSON.Assemble {

    @inlinable
    package static func from(_ events: inout JSON.Span.EventStream) throws(JSON.Error) -> JSON {
        do throws(RFC_8259.Error) {
            let value = try Lexer.Pull.Assemble.from(&events.inner, strategy: JSON.Assemble.self)
            return JSON(value)
        } catch {
            throw JSON.Error(error)
        }
    }
}
