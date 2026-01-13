/// JSON
/// swift-json
///
/// A modern, type-safe JSON API for Swift 6.2+
///
/// ## Overview
///
/// `JSON` is both a namespace and a value type, providing an ergonomic API
/// for working with JSON data in Swift.
///
/// ## Construction
///
/// ```swift
/// // Via literals
/// let json: JSON = [
///     "name": "John",
///     "age": 30,
///     "verified": true,
///     "tags": ["swift", "json"]
/// ]
///
/// // Via parsing
/// let json = try JSON.parse(jsonString)
/// ```
///
/// ## Access
///
/// ```swift
/// // Value extraction via initializers
/// String(json.name)           // "John" (empty string if not a string)
/// String?(json.name)          // Optional("John")
/// Int(json.age)               // Optional(30)
/// Bool(json.verified)         // Optional(true)
///
/// // Dynamic member lookup for navigation
/// json.user.name              // JSON value
/// json["user"]["name"]        // Same via subscript
/// json.tags[0]                // Array access
///
/// // Collection access
/// json.array                  // Optional([JSON])
/// json.dictionary             // Optional([String: JSON])
/// ```
///
/// ## Serialization
///
/// ```swift
/// let string = json.serialize()
/// let pretty = json.serialize(pretty: true)
/// ```

import RFC_8259

/// A JSON value.
///
/// `JSON` represents any valid JSON value: null, boolean, number, string,
/// array, or object. It provides type-safe access and ergonomic APIs for
/// working with JSON data.
@dynamicMemberLookup
public struct JSON: Sendable, Hashable {
    /// The underlying RFC 8259 value.
    @usableFromInline
    internal var raw: RFC_8259.Value

    /// Creates a JSON value from an RFC 8259 value.
    @inlinable
    public init(_ raw: RFC_8259.Value) {
        self.raw = raw
    }
}

// MARK: - Case Constructors

extension JSON {
    /// A JSON null value.
    public static let null = JSON(.null)

    /// Creates a JSON boolean.
    @inlinable
    public static func bool(_ value: Bool) -> JSON {
        JSON(.bool(value))
    }

    /// Creates a JSON number from an integer.
    @inlinable
    public static func number(_ value: Int) -> JSON {
        JSON(.number(RFC_8259.Number(value)))
    }

    /// Creates a JSON number from a floating-point value.
    @inlinable
    public static func number(_ value: Double) -> JSON {
        JSON(.number(RFC_8259.Number(value)))
    }

    /// Creates a JSON string.
    @inlinable
    public static func string(_ value: String) -> JSON {
        JSON(.string(value))
    }

    /// Creates a JSON array.
    @inlinable
    public static func array(_ elements: [JSON]) -> JSON {
        JSON(.array(RFC_8259.Array(elements.map(\.raw))))
    }

    /// Creates a JSON object.
    @inlinable
    public static func object(_ members: [(String, JSON)]) -> JSON {
        JSON(.object(RFC_8259.Object(members.map { ($0.0, $0.1.raw) })))
    }
}

// MARK: - Type Checking

extension JSON {
    /// Returns `true` if this is a null value.
    @inlinable
    public var isNull: Bool {
        if case .null = raw { return true }
        return false
    }

    /// Returns `true` if this is a boolean value.
    @inlinable
    public var isBool: Bool {
        if case .bool = raw { return true }
        return false
    }

    /// Returns `true` if this is a number value.
    @inlinable
    public var isNumber: Bool {
        if case .number = raw { return true }
        return false
    }

    /// Returns `true` if this is a string value.
    @inlinable
    public var isString: Bool {
        if case .string = raw { return true }
        return false
    }

    /// Returns `true` if this is an array value.
    @inlinable
    public var isArray: Bool {
        if case .array = raw { return true }
        return false
    }

    /// Returns `true` if this is an object value.
    @inlinable
    public var isObject: Bool {
        if case .object = raw { return true }
        return false
    }
}

// MARK: - Collection Access

extension JSON {
    /// The array elements, if this is an array.
    @inlinable
    public var array: [JSON]? {
        guard case .array(let a) = raw else { return nil }
        return a.map(JSON.init)
    }

    /// The object members as key-value pairs, if this is an object.
    @inlinable
    public var object: [(key: String, value: JSON)]? {
        guard case .object(let o) = raw else { return nil }
        return o.map { (key: $0.key, value: JSON($0.value)) }
    }

    /// The object as a dictionary, if this is an object.
    ///
    /// Note: If duplicate keys exist, later values overwrite earlier ones.
    @inlinable
    public var dictionary: [String: JSON]? {
        guard case .object(let o) = raw else { return nil }
        var dict: [String: JSON] = [:]
        for member in o {
            dict[member.key] = JSON(member.value)
        }
        return dict
    }
}

// MARK: - Subscripts

extension JSON {
    /// Accesses the value for the given key in an object.
    ///
    /// Returns `.null` if this is not an object or the key doesn't exist.
    @inlinable
    public subscript(key: String) -> JSON {
        guard case .object(let o) = raw else { return .null }
        guard let value = o[key] else { return .null }
        return JSON(value)
    }

    /// Accesses the element at the given index in an array.
    ///
    /// Returns `.null` if this is not an array or the index is out of bounds.
    @inlinable
    public subscript(index: Int) -> JSON {
        guard case .array(let a) = raw else { return .null }
        guard index >= 0 && index < a.count else { return .null }
        return JSON(a[index])
    }
}

// MARK: - Dynamic Member Lookup

extension JSON {
    /// Accesses a member of an object by name.
    ///
    /// Enables `json.user.name` syntax instead of `json["user"]["name"]`.
    @inlinable
    public subscript(dynamicMember member: String) -> JSON {
        self[member]
    }
}

// MARK: - Parsing

extension JSON {
    /// Parses JSON from a string.
    ///
    /// - Parameter string: The JSON string to parse.
    /// - Returns: The parsed JSON value.
    /// - Throws: `JSON.Error` if parsing fails.
    @inlinable
    public static func parse(_ string: String) throws(JSON.Error) -> JSON {
        do {
            let value = try RFC_8259.parse(string)
            return JSON(value)
        } catch {
            throw JSON.Error(error)
        }
    }

    /// Parses JSON from UTF-8 bytes.
    ///
    /// - Parameter bytes: The UTF-8 encoded JSON bytes.
    /// - Returns: The parsed JSON value.
    /// - Throws: `JSON.Error` if parsing fails.
    @inlinable
    public static func parse<Bytes>(_ bytes: Bytes) throws(JSON.Error) -> JSON
    where Bytes: Collection<UInt8>, Bytes: Sendable, Bytes.Index: Sendable {
        do {
            let value = try RFC_8259.parse(bytes)
            return JSON(value)
        } catch {
            throw JSON.Error(error)
        }
    }
}

// MARK: - Serialization

extension JSON {
    /// Serializes the JSON value to a string.
    ///
    /// - Parameters:
    ///   - pretty: Whether to format with indentation and newlines.
    ///   - sortKeys: Whether to sort object keys alphabetically.
    /// - Returns: The JSON string.
    @inlinable
    public func serialize(pretty: Bool = false, sortKeys: Bool = false) -> String {
        let options = RFC_8259.Options(prettyPrint: pretty, sortKeys: sortKeys)
        let bytes = raw.encode(options: options)
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Serializes the JSON value to UTF-8 bytes.
    ///
    /// - Parameters:
    ///   - pretty: Whether to format with indentation and newlines.
    ///   - sortKeys: Whether to sort object keys alphabetically.
    /// - Returns: The UTF-8 encoded JSON bytes.
    @inlinable
    public func serialize(pretty: Bool = false, sortKeys: Bool = false, as: [UInt8].Type) -> [UInt8] {
        let options = RFC_8259.Options(prettyPrint: pretty, sortKeys: sortKeys)
        return raw.encode(options: options)
    }
}

// MARK: - Count

extension JSON {
    /// The number of elements in an array or members in an object.
    ///
    /// Returns `nil` for non-container types.
    @inlinable
    public var count: Int? {
        switch raw {
        case .array(let a): return a.count
        case .object(let o): return o.count
        default: return nil
        }
    }

    /// Whether this is an empty array or object.
    ///
    /// Returns `nil` for non-container types.
    @inlinable
    public var isEmpty: Bool? {
        switch raw {
        case .array(let a): return a.isEmpty
        case .object(let o): return o.isEmpty
        default: return nil
        }
    }
}
