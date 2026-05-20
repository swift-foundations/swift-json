/// JSON.Serializable.swift
/// swift-json
///
/// JSON.Serializable is the JSON sibling of the format-Codable family,
/// mirroring the parser-side Parseable / ASCII.Parseable convention.
///
/// ## Family pattern
///
/// The institute's `Coder_Primitives.Coder.Protocol` is a generic
/// leaf-codec abstraction; one Coder per (format × value) pair.
/// `Coder_Primitives.Codable` is the canonical attachment for types
/// that have ONE inherent canonical codec — e.g., `RFC_8259.Value:
/// Codable` with `coder = JSON.Coder()`.
///
/// Stdlib types (Int, String, Optional, Array, Dictionary, ...) do
/// not have a single inherent canonical codec — their representation
/// is format-specific. So they conform to FORMAT-SPECIFIC sibling
/// protocols like `JSON.Serializable`, `Binary.Serializable` +
/// `Binary.Parseable` (the split-pair per [FAM-005]; the legacy
/// `Binary.LittleEndian.Codable` framing has been replaced), etc.,
/// rather than to the generic `Codable`. This mirrors the parser-side
/// pattern where `Int: ASCII.Parseable` lives in
/// swift-ascii-parser-primitives (format-specific) rather than as a
/// generic `Int: Parseable`.
///
/// ## Composition with the canonical leaf
///
/// JSON.Serializable's `init(jsonBytes:)` path composes through
/// `JSON.Decode.Implementation.parse` — the same leaf that
/// `RFC_8259.Value.coder` uses. There's no parallel grammar; this
/// protocol is the JSON-specific surface (event-grain streaming
/// fast path, format-aware Optional null-sentinel semantics,
/// ergonomic per-type API) over the same canonical leaf.
///
/// ## When to use which
///
/// - Use `RFC_8259.Value(decoding: &input)` (canonical Codable) when
///   you have a span of bytes and want the full JSON value tree.
/// - Use `T(json:)` / `T.from(eventDecodingJsonBytes:)` (this protocol)
///   when you have a JSON value or bytes and want to deserialize to
///   a JSON.Serializable conformer.
/// - The two compose; `JSON.parse(bytes) → JSON → T(json:)` and
///   `T.from(eventDecodingJsonBytes: bytes)` use the same underlying
///   leaf parser.

extension JSON {
    /// A type that can be serialized to and deserialized from JSON.
    ///
    /// Conform to this protocol to enable direct JSON serialization without
    /// going through Codable. This provides clearer semantics and can be
    /// more efficient.
    ///
    /// ## Role in the format-Codable family
    ///
    /// JSON.Serializable is a sibling protocol to `Coder_Primitives.Codable`
    /// rather than a refinement. A type conforming to JSON.Serializable
    /// declares its JSON representation; a type conforming to
    /// `Coder_Primitives.Codable` declares its canonical inherent codec.
    /// Types that have both (`RFC_8259.Value`) carry both conformances
    /// pointing to the same underlying leaf (JSON.Coder). Types whose
    /// representation is format-specific (most stdlib types, most
    /// user-defined types) conform to JSON.Serializable but typically
    /// NOT to the generic Codable — they may additionally conform to
    /// sibling protocols for other formats (`Binary.Serializable` +
    /// `Binary.Parseable` per [FAM-005], `MessagePack.Serializable`
    /// future, etc.).
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct User: JSON.Serializable {
    ///     let name: String
    ///     let age: Int
    ///
    ///     static func serialize(_ value: User) -> JSON {
    ///         [
    ///             "name": .string(value.name),
    ///             "age": .number(value.age)
    ///         ]
    ///     }
    ///
    ///     static func deserialize(_ json: JSON) throws(JSON.Error) -> User {
    ///         guard let name = json.name.string else {
    ///             throw .missingKey("name")
    ///         }
    ///         guard let age = json.age.int else {
    ///             throw .missingKey("age")
    ///         }
    ///         return User(name: name, age: age)
    ///     }
    /// }
    ///
    /// // Usage
    /// let json = user.json
    /// let user = try User(json: json)
    /// ```
    public protocol Serializable {
        /// Serializes this value to a JSON representation.
        static func serialize(_ value: Self) -> JSON

        /// Deserializes a JSON value to this type.
        ///
        /// - Parameter json: The JSON value to deserialize.
        /// - Returns: The deserialized value.
        /// - Throws: `JSON.Error` if deserialization fails.
        static func deserialize(_ json: JSON) throws(JSON.Error) -> Self

        /// Deserializes from a pull-driven event stream — the opt-in
        /// fast path that skips full-tree materialisation.
        ///
        /// Default implementation in the protocol extension delegates
        /// to `JSON.Assemble.from(_:)` → `deserialize(_: JSON)`. The
        /// default's fast path short-circuits to the existing tree
        /// builder when the stream is unforked at position 0 (per the
        /// streaming-deserialize arc's binding A1 constraint
        /// §9.3 mitigation 1), so existing conformers do NOT regress.
        ///
        /// Opt-in consumers override this with a byte-to-target body
        /// that uses `events.next()` / `currentString()` /
        /// `currentNumber()` / `skipValue()` directly. Skipping
        /// undeclared fields via `skipValue()` is the structural fix
        /// to the 37% partial-shape decode gap to Foundation
        /// `JSONDecoder` (per
        /// `streaming-json-deserialize-status-quo-and-prior-art.md`
        /// v1.0.0).
        ///
        /// - Parameter events: An `inout` event stream. The conformer
        ///   consumes events until it has produced one complete value.
        /// - Returns: The deserialized value.
        /// - Throws: `JSON.Error` if deserialization fails.
        static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> Self
    }
}

// MARK: - Default Event-Stream Deserialize

extension JSON.Serializable {
    /// Default fallback: assemble a `JSON` value from the event stream,
    /// then delegate to the existing tree-grain `deserialize(_:)`.
    ///
    /// Existing conformers inherit this for free; no source break.
    /// Per A0 §9.3 the helper's FAST PATH short-circuits to
    /// `RFC_8259.Span.Parser.parse(_:)` when the stream is unforked
    /// at position 0, so the default-fallback's call graph collapses
    /// to today's `init(jsonBytes:)` path on every existing conformer.
    ///
    /// Opt-in consumers override this method directly with a
    /// byte-to-target body. The contribution of Option B is the
    /// shape of the override — see
    /// `streaming-json-deserialize-comparative-analysis.md` v1.0.1
    /// §4.6 for the end-to-end example.
    @inlinable
    public static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> Self {
        let json = try JSON.Assemble.from(&events)
        return try Self.deserialize(json)
    }
}

// MARK: - Convenience Extensions

extension JSON.Serializable {
    /// Converts this value to JSON.
    @inlinable
    public var json: JSON {
        Self.serialize(self)
    }

    /// Creates an instance from a JSON value.
    ///
    /// - Parameter json: The JSON value to deserialize.
    /// - Throws: `JSON.Error` if deserialization fails.
    @inlinable
    public init(json: JSON) throws(JSON.Error) {
        self = try Self.deserialize(json)
    }

    /// Creates an instance from a JSON string.
    ///
    /// - Parameter jsonString: The JSON string to parse and deserialize.
    /// - Throws: `JSON.Error` if parsing or deserialization fails.
    @inlinable
    public init(jsonString: String) throws(JSON.Error) {
        let json = try JSON.parse(jsonString)
        self = try Self.deserialize(json)
    }

    /// Creates an instance from UTF-8 JSON bytes.
    ///
    /// - Parameter jsonBytes: The UTF-8 encoded JSON to parse and deserialize.
    /// - Throws: `JSON.Error` if parsing or deserialization fails.
    @inlinable
    public init<Bytes>(jsonBytes: Bytes) throws(JSON.Error)
    where Bytes: Swift.Collection<UInt8>, Bytes: Sendable, Bytes.Index: Sendable {
        let json = try JSON.parse(jsonBytes)
        self = try Self.deserialize(json)
    }

    /// Creates an instance from UTF-8 JSON bytes via the event-grain
    /// fast path.
    ///
    /// Conformers that have overridden `deserialize(events:)` get the
    /// fast path (byte-to-target without intermediate tree
    /// materialisation); conformers that haven't get the default
    /// (full-tree fallback, equivalent to the existing
    /// `init(jsonBytes:)` via the §4.3 short-circuit per A0 §9.3).
    ///
    /// Dispatches on contiguous storage — mirrors the
    /// `RFC_8259.Decode` pattern. Static method returning `Self`
    /// rather than an `init` because protocol-extension `init` does
    /// not dispatch through the witness table the way methods do;
    /// the static method ensures correct dispatch into the
    /// conformer's override.
    ///
    /// - Parameter bytes: The UTF-8 encoded JSON.
    /// - Returns: The deserialized value.
    /// - Throws: `JSON.Error` if parsing or deserialization fails.
    @inlinable
    public static func from<Bytes>(eventDecodingJsonBytes bytes: Bytes) throws(JSON.Error) -> Self
    where Bytes: Swift.Collection<UInt8>, Bytes: Sendable, Bytes.Index: Sendable {
        // Fast path: contiguous storage → Span cursor.
        var parserError: JSON.Error? = nil
        let fastResult: Self? = bytes.withContiguousStorageIfAvailable {
            (buffer: UnsafeBufferPointer<UInt8>) -> Self? in
            let span = buffer.span
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
        } ?? nil
        if let value = fastResult { return value }
        if let err = parserError { throw err }
        // Slow path: arbitrary Collection<UInt8>.
        let array = Swift.Array(bytes)
        var slowError: JSON.Error? = nil
        let result: Self? = array.withUnsafeBufferPointer { buffer -> Self? in
            let span = buffer.span
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

    /// Serializes this value to a JSON string.
    ///
    /// - Parameters:
    ///   - pretty: Whether to format with indentation and newlines.
    ///   - sortKeys: Whether to sort object keys alphabetically.
    /// - Returns: The JSON string representation.
    @inlinable
    public func jsonString(pretty: Bool = false, sortKeys: Bool = false) -> String {
        json.serialize(pretty: pretty, sortKeys: sortKeys)
    }

    /// Serializes this value to UTF-8 JSON bytes.
    ///
    /// - Parameters:
    ///   - pretty: Whether to format with indentation and newlines.
    ///   - sortKeys: Whether to sort object keys alphabetically.
    /// - Returns: The UTF-8 encoded JSON bytes.
    @inlinable
    public func jsonBytes(pretty: Bool = false, sortKeys: Bool = false) -> [UInt8] {
        json.serialize(pretty: pretty, sortKeys: sortKeys, as: [UInt8].self)
    }
}

// MARK: - JSON is Serializable

extension JSON: JSON.Serializable {
    @inlinable
    public static func serialize(_ value: JSON) -> JSON {
        value
    }

    @inlinable
    public static func deserialize(_ json: JSON) throws(JSON.Error) -> JSON {
        json
    }

    /// Event-grain deserialize for `JSON` itself. Assembles the
    /// full tree from events (uses the §4.3 short-circuit when the
    /// stream is unforked).
    @inlinable
    public static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> JSON {
        try JSON.Assemble.from(&events)
    }
}

// MARK: - Standard Type Conformances

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
    public static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> String {
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
        case .`true`:  return true
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
    public static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> Int64 {
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
    public static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> Double {
        guard let token = try events.next() else {
            throw .typeMismatch(expected: "double", got: "end of input")
        }
        guard token == .number else {
            throw .typeMismatch(expected: "double", got: token.description)
        }
        let number = try events.currentNumber()
        return number.double ?? Double(number.int64 ?? 0)
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
    public static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> [Element] {
        try events.expectArrayStart()
        var result: [Element] = []
        // Empty-array detection: peek for ']' without consuming a
        // token, so Element.deserialize(events:) can drive its own
        // next() on a non-empty path.
        if events.peekStructural() == UInt8(ascii: "]") {
            _ = try events.next() // consume ']'
            return result
        }
        // First element — Element drives its own next().
        result.append(try Element.deserialize(events: &events))

        while true {
            guard let next = try events.next() else {
                throw .invalidSyntax(message: "Unexpected end of input in array", location: events.position().location)
            }
            switch next {
            case .arrayEnd:
                return result
            case .comma:
                result.append(try Element.deserialize(events: &events))
            default:
                throw .invalidSyntax(message: "Expected ',' or ']', got \(next.description)", location: events.position().location)
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
    public static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> [String: Value] {
        try events.expectObjectStart()
        var result: [String: Value] = [:]
        if events.peekStructural() == UInt8(ascii: "}") {
            _ = try events.next() // consume '}'
            return result
        }
        // First member: key (string) : value
        guard let firstKeyToken = try events.next() else {
            throw .invalidSyntax(message: "Unexpected end of input in object", location: events.position().location)
        }
        guard firstKeyToken == .string else {
            throw .invalidSyntax(message: "Expected object key (string), got \(firstKeyToken.description)", location: events.position().location)
        }
        let firstKey = try events.currentString()
        try events.expectColon()
        result[firstKey] = try Value.deserialize(events: &events)

        while true {
            guard let next = try events.next() else {
                throw .invalidSyntax(message: "Unexpected end of input in object", location: events.position().location)
            }
            switch next {
            case .objectEnd:
                return result
            case .comma:
                guard let keyToken = try events.next() else {
                    throw .invalidSyntax(message: "Unexpected end of input after ','", location: events.position().location)
                }
                guard keyToken == .string else {
                    throw .invalidSyntax(message: "Expected object key (string), got \(keyToken.description)", location: events.position().location)
                }
                let key = try events.currentString()
                try events.expectColon()
                result[key] = try Value.deserialize(events: &events)
            default:
                throw .invalidSyntax(message: "Expected ',' or '}', got \(next.description)", location: events.position().location)
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
    public static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> Wrapped? {
        // Peek at the structural byte to detect null without consuming.
        // 'n' is the first byte of `null`; any other byte routes to
        // Wrapped.deserialize(events:).
        if events.peekStructural() == UInt8(ascii: "n") {
            guard let token = try events.next() else {
                throw .invalidSyntax(message: "Unexpected end of input", location: events.position().location)
            }
            guard token == .null else {
                throw .typeMismatch(expected: "value or null", got: token.description)
            }
            return nil
        }
        return try Wrapped.deserialize(events: &events)
    }
}

// MARK: - Type Name Helper

extension JSON {
    /// The name of the JSON type for error messages.
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
