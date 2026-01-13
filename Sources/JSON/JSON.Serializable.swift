/// JSON.Serializable.swift
/// swift-json
///
/// Protocol for types that can be serialized to/from JSON

extension JSON {
    /// A type that can be serialized to and deserialized from JSON.
    ///
    /// Conform to this protocol to enable direct JSON serialization without
    /// going through Codable. This provides clearer semantics and can be
    /// more efficient.
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
    where Bytes: Collection<UInt8>, Bytes: Sendable, Bytes.Index: Sendable {
        let json = try JSON.parse(jsonBytes)
        self = try Self.deserialize(json)
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
}

// MARK: - Standard Type Conformances

extension String: JSON.Serializable {
    @inlinable
    public static func serialize(_ value: String) -> JSON {
        .string(value)
    }

    @inlinable
    public static func deserialize(_ json: JSON) throws(JSON.Error) -> String {
        guard let value = json.string else {
            throw .typeMismatch(expected: "string", got: json.typeName)
        }
        return value
    }
}

extension Bool: JSON.Serializable {
    @inlinable
    public static func serialize(_ value: Bool) -> JSON {
        .bool(value)
    }

    @inlinable
    public static func deserialize(_ json: JSON) throws(JSON.Error) -> Bool {
        guard let value = json.bool else {
            throw .typeMismatch(expected: "bool", got: json.typeName)
        }
        return value
    }
}

extension Int: JSON.Serializable {
    @inlinable
    public static func serialize(_ value: Int) -> JSON {
        .number(value)
    }

    @inlinable
    public static func deserialize(_ json: JSON) throws(JSON.Error) -> Int {
        guard let value = json.int else {
            throw .typeMismatch(expected: "int", got: json.typeName)
        }
        return value
    }
}

extension Int64: JSON.Serializable {
    @inlinable
    public static func serialize(_ value: Int64) -> JSON {
        let str = String(value)
        let number = RFC_8259.Number(value, original: .init(Array(str.utf8)))
        return JSON(.number(number))
    }

    @inlinable
    public static func deserialize(_ json: JSON) throws(JSON.Error) -> Int64 {
        guard let value = json.int64 else {
            throw .typeMismatch(expected: "int64", got: json.typeName)
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
        guard let value = json.double else {
            throw .typeMismatch(expected: "double", got: json.typeName)
        }
        return value
    }
}

extension Array: JSON.Serializable where Element: JSON.Serializable {
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
