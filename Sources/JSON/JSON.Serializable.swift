extension JSON {

    public protocol Serializable {

        static func serialize(_ value: Self) -> JSON

        static func deserialize(_ json: JSON) throws(JSON.Error) -> Self

        static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> Self
    }
}

extension JSON.Serializable {

    @inlinable
    public static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> Self {
        let json = try JSON.Assemble.from(&events)
        return try Self.deserialize(json)
    }
}

extension JSON.Serializable {

    @inlinable
    public var json: JSON {
        Self.serialize(self)
    }

    @inlinable
    public init(json: JSON) throws(JSON.Error) {
        self = try Self.deserialize(json)
    }

    @inlinable
    public init(jsonString: String) throws(JSON.Error) {
        let json = try JSON.parse(jsonString)
        self = try Self.deserialize(json)
    }

    @inlinable
    public init<Bytes>(jsonBytes: Bytes) throws(JSON.Error)
    where Bytes: Swift.Collection<Byte>, Bytes: Sendable, Bytes.Index: Sendable {
        let json = try JSON.parse(jsonBytes)
        self = try Self.deserialize(json)
    }

    @inlinable
    public static func from<Bytes>(eventDecodingJsonBytes bytes: Bytes) throws(JSON.Error) -> Self
    where Bytes: Swift.Collection<Byte>, Bytes: Sendable, Bytes.Index: Sendable {

        var parserError: JSON.Error? = nil
        let fastResult: Self? =
            bytes.withContiguousStorageIfAvailable {
                (buffer: UnsafeBufferPointer<Byte>) -> Self? in
                let span = unsafe buffer.span
                var stream = JSON.Span.EventStream(span)
                do {
                    return try Self.deserialize(events: &stream)
                } catch let error as JSON.Error {
                    parserError = error
                    return nil
                } catch {
                    parserError = .unknown
                    return nil
                }
            }
            .flatMap { $0 }
        if let value = fastResult { return value }
        if let err = parserError { throw err }

        let array = Swift.Array(bytes)
        var slowError: JSON.Error? = nil
        let result: Self? = array.withUnsafeBufferPointer { buffer -> Self? in
            let span = unsafe buffer.span
            var stream = JSON.Span.EventStream(span)
            do {
                return try Self.deserialize(events: &stream)
            } catch let error as JSON.Error {
                slowError = error
                return nil
            } catch {
                slowError = .unknown
                return nil
            }
        }
        if let value = result { return value }
        if let err = slowError { throw err }
        throw .unknown
    }

    @inlinable
    public func jsonString(pretty: Bool = false, sortKeys: Bool = false) -> String {
        json.serialize(pretty: pretty, sortKeys: sortKeys)
    }

    @inlinable
    public func jsonBytes(pretty: Bool = false, sortKeys: Bool = false) -> [UInt8] {
        json.serialize(pretty: pretty, sortKeys: sortKeys, as: [UInt8].self)
    }
}

extension JSON: JSON.Serializable {
    @inlinable
    public static func serialize(_ value: JSON) -> JSON {
        value
    }

    @inlinable
    public static func deserialize(_ json: JSON) throws(JSON.Error) -> JSON {
        json
    }

    @inlinable
    public static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> JSON {
        try JSON.Assemble.from(&events)
    }
}

extension String: JSON.Serializable {
    @inlinable
    public static func serialize(_ value: String) -> JSON {
        .string(value)
    }

    @inlinable
    public static func deserialize(_ json: JSON) throws(JSON.Error) -> String {
        guard case .string(let value) = json.raw else {
            throw .typeMismatch(expected: "string", got: json.typeName)
        }
        return value
    }

    @inlinable
    public static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> String
    {
        guard let token = try events.next() else {
            throw .typeMismatch(expected: "string", got: "end of input")
        }
        guard token == .string else {
            throw .typeMismatch(expected: "string", got: token.description)
        }
        return try events.currentString()
    }
}

extension Bool: JSON.Serializable {
    @inlinable
    public static func serialize(_ value: Bool) -> JSON {
        .bool(value)
    }

    @inlinable
    public static func deserialize(_ json: JSON) throws(JSON.Error) -> Bool {
        guard let value = Bool(json) else {
            throw .typeMismatch(expected: "bool", got: json.typeName)
        }
        return value
    }

    @inlinable
    public static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> Bool {
        guard let token = try events.next() else {
            throw .typeMismatch(expected: "bool", got: "end of input")
        }
        switch token {
        case .`true`: return true
        case .`false`: return false

        default:
            throw .typeMismatch(expected: "bool", got: token.description)
        }
    }
}

extension Int: JSON.Serializable {
    @inlinable
    public static func serialize(_ value: Int) -> JSON {
        .number(value)
    }

    @inlinable
    public static func deserialize(_ json: JSON) throws(JSON.Error) -> Int {
        guard let value = Int(json) else {
            throw .typeMismatch(expected: "int", got: json.typeName)
        }
        return value
    }

    @inlinable
    public static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> Int {
        guard let token = try events.next() else {
            throw .typeMismatch(expected: "int", got: "end of input")
        }
        guard token == .number else {
            throw .typeMismatch(expected: "int", got: token.description)
        }
        let number = try events.currentNumber()
        guard let int64 = number.int64, let value = Int(exactly: int64) else {
            throw .typeMismatch(expected: "int", got: "number out of range")
        }
        return value
    }
}

extension Int64: JSON.Serializable {
    @inlinable
    public static func serialize(_ value: Int64) -> JSON {
        let str = String(value)
        let number = RFC_8259.Number(value, original: .init(Swift.Array(str.utf8)))
        return JSON(.number(number))
    }

    @inlinable
    public static func deserialize(_ json: JSON) throws(JSON.Error) -> Int64 {
        guard let value = Int64(json) else {
            throw .typeMismatch(expected: "int64", got: json.typeName)
        }
        return value
    }

    @inlinable
    public static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> Int64
    {
        guard let token = try events.next() else {
            throw .typeMismatch(expected: "int64", got: "end of input")
        }
        guard token == .number else {
            throw .typeMismatch(expected: "int64", got: token.description)
        }
        let number = try events.currentNumber()
        guard let value = number.int64 else {
            throw .typeMismatch(expected: "int64", got: "number out of range")
        }
        return value
    }
}

extension Double: JSON.Serializable {
    @inlinable
    public static func serialize(_ value: Double) -> JSON {
        .number(value)
    }

    @inlinable
    public static func deserialize(_ json: JSON) throws(JSON.Error) -> Double {
        guard let value = Double(json) else {
            throw .typeMismatch(expected: "double", got: json.typeName)
        }
        return value
    }

    @inlinable
    public static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> Double
    {
        guard let token = try events.next() else {
            throw .typeMismatch(expected: "double", got: "end of input")
        }
        guard token == .number else {
            throw .typeMismatch(expected: "double", got: token.description)
        }
        let number = try events.currentNumber()
        return number.double
    }
}

extension Swift.Array: JSON.Serializable where Element: JSON.Serializable {
    @inlinable
    public static func serialize(_ value: [Element]) -> JSON {
        .array(value.map { $0.json })
    }

    @inlinable
    public static func deserialize(_ json: JSON) throws(JSON.Error) -> [Element] {
        guard let array = json.array else {
            throw .typeMismatch(expected: "array", got: json.typeName)
        }
        var result: [Element] = []
        result.reserveCapacity(array.count)
        for element in array {
            result.append(try Element(json: element))
        }
        return result
    }

    @inlinable
    public static func deserialize(
        events: inout JSON.Span.EventStream
    ) throws(JSON.Error) -> [Element] {
        try events.expectArrayStart()
        var result: [Element] = []

        if events.peekStructural() == UInt8(ascii: "]") {
            _ = try events.next()
            return result
        }

        result.append(try Element.deserialize(events: &events))

        while true {
            guard let next = try events.next() else {
                throw .invalidSyntax(
                    message: "Unexpected end of input in array",
                    location: events.position().location
                )
            }
            switch next {
            case .arrayEnd:
                return result

            case .comma:
                result.append(try Element.deserialize(events: &events))

            default:
                throw .invalidSyntax(
                    message: "Expected ',' or ']', got \(next.description)",
                    location: events.position().location
                )
            }
        }
    }
}

extension Dictionary: JSON.Serializable where Key == String, Value: JSON.Serializable {
    @inlinable
    public static func serialize(_ value: [String: Value]) -> JSON {
        .object(value.map { ($0.key, $0.value.json) })
    }

    @inlinable
    public static func deserialize(_ json: JSON) throws(JSON.Error) -> [String: Value] {
        guard let object = json.object else {
            throw .typeMismatch(expected: "object", got: json.typeName)
        }
        var result: [String: Value] = [:]
        for (key, value) in object {
            result[key] = try Value(json: value)
        }
        return result
    }

    @inlinable
    public static func deserialize(
        events: inout JSON.Span.EventStream
    ) throws(JSON.Error) -> [String: Value] {
        try events.expectObjectStart()
        var result: [String: Value] = [:]
        if events.peekStructural() == UInt8(ascii: "}") {
            _ = try events.next()
            return result
        }

        guard let firstKeyToken = try events.next() else {
            throw .invalidSyntax(
                message: "Unexpected end of input in object",
                location: events.position().location
            )
        }
        guard firstKeyToken == .string else {
            throw .invalidSyntax(
                message: "Expected object key (string), got \(firstKeyToken.description)",
                location: events.position().location
            )
        }
        let firstKey = try events.currentString()
        try events.expectColon()
        result[firstKey] = try Value.deserialize(events: &events)

        while true {
            guard let next = try events.next() else {
                throw .invalidSyntax(
                    message: "Unexpected end of input in object",
                    location: events.position().location
                )
            }
            switch next {
            case .objectEnd:
                return result

            case .comma:
                guard let keyToken = try events.next() else {
                    throw .invalidSyntax(
                        message: "Unexpected end of input after ','",
                        location: events.position().location
                    )
                }
                guard keyToken == .string else {
                    throw .invalidSyntax(
                        message: "Expected object key (string), got \(keyToken.description)",
                        location: events.position().location
                    )
                }
                let key = try events.currentString()
                try events.expectColon()
                result[key] = try Value.deserialize(events: &events)

            default:
                throw .invalidSyntax(
                    message: "Expected ',' or '}', got \(next.description)",
                    location: events.position().location
                )
            }
        }
    }
}

extension Optional: JSON.Serializable where Wrapped: JSON.Serializable {
    @inlinable
    public static func serialize(_ value: Wrapped?) -> JSON {
        guard let value else { return .null }
        return value.json
    }

    @inlinable
    public static func deserialize(_ json: JSON) throws(JSON.Error) -> Wrapped? {
        if json.isNull { return nil }
        return try Wrapped(json: json)
    }

    @inlinable
    public static func deserialize(
        events: inout JSON.Span.EventStream
    ) throws(JSON.Error) -> Wrapped? {

        if events.peekStructural() == UInt8(ascii: "n") {
            guard let token = try events.next() else {
                throw .invalidSyntax(
                    message: "Unexpected end of input",
                    location: events.position().location
                )
            }
            guard token == .null else {
                throw .typeMismatch(expected: "value or null", got: token.description)
            }
            return nil
        }
        return try Wrapped.deserialize(events: &events)
    }
}

extension JSON {

    @usableFromInline
    internal var typeName: String {
        switch raw {
        case .null: return "null"
        case .bool: return "bool"
        case .number: return "number"
        case .string: return "string"
        case .array: return "array"
        case .object: return "object"
        }
    }
}
