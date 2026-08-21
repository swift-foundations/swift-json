import RFC_8259

@dynamicMemberLookup
public struct JSON: Sendable, Hashable {

    @usableFromInline
    internal var raw: RFC_8259.Value

    @inlinable
    public init(_ raw: RFC_8259.Value) {
        self.raw = raw
    }
}

extension JSON {

    public static let null = JSON(.null)

    @inlinable
    public static func bool(_ value: Bool) -> JSON {
        JSON(.bool(value))
    }

    @inlinable
    public static func number(_ value: Int) -> JSON {
        JSON(.number(RFC_8259.Number(value)))
    }

    @inlinable
    public static func number(_ value: Double) -> JSON {
        JSON(.number(RFC_8259.Number(value)))
    }

    @inlinable
    public static func string(_ value: String) -> JSON {
        JSON(.string(value))
    }

    @inlinable
    public static func array(_ elements: [JSON]) -> JSON {
        JSON(.array(RFC_8259.Array(elements.map { $0.raw })))
    }

    @inlinable
    public static func object(_ members: [(String, JSON)]) -> JSON {
        JSON(.object(RFC_8259.Object(members.map { ($0.0, $0.1.raw) })))
    }
}

extension JSON {

    @inlinable
    public var isNull: Bool {
        if case .null = raw { return true }
        return false
    }

    @inlinable
    public var isBool: Bool {
        if case .bool = raw { return true }
        return false
    }

    @inlinable
    public var isNumber: Bool {
        if case .number = raw { return true }
        return false
    }

    @inlinable
    public var isString: Bool {
        if case .string = raw { return true }
        return false
    }

    @inlinable
    public var isArray: Bool {
        if case .array = raw { return true }
        return false
    }

    @inlinable
    public var isObject: Bool {
        if case .object = raw { return true }
        return false
    }
}

extension JSON {

    @inlinable
    public var array: [JSON]? {
        guard case .array(let a) = raw else { return nil }
        return a.map(JSON.init)
    }

    @inlinable
    public var object: [(key: String, value: JSON)]? {
        guard case .object(let o) = raw else { return nil }
        return o.map { (key: $0.key, value: JSON($0.value)) }
    }

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

extension JSON {

    @inlinable
    public subscript(key: String) -> JSON {
        guard case .object(let o) = raw else { return .null }
        guard let value = o[key] else { return .null }
        return JSON(value)
    }

    @inlinable
    public subscript(index: Int) -> JSON {
        guard case .array(let a) = raw else { return .null }
        guard index >= 0 && index < a.count else { return .null }
        return JSON(a[index])
    }
}

extension JSON {

    @inlinable
    public subscript(dynamicMember member: String) -> JSON {
        self[member]
    }
}

extension JSON {

    @inlinable
    public static func parse(_ string: String) throws(JSON.Error) -> JSON {
        do throws(RFC_8259.Error) {
            let value = try JSON.Decode.parse(string)
            return JSON(value)
        } catch {
            throw JSON.Error(error)
        }
    }

    @inlinable
    public static func parse<Bytes>(_ bytes: Bytes) throws(JSON.Error) -> JSON
    where Bytes: Swift.Collection<Byte>, Bytes: Sendable, Bytes.Index: Sendable {
        do throws(RFC_8259.Error) {
            let value = try JSON.Decode.parse(bytes)
            return JSON(value)
        } catch {
            throw JSON.Error(error)
        }
    }
}

extension JSON {

    @inlinable
    public func serialize(pretty: Bool = false, sortKeys: Bool = false) -> String {
        let options = JSON.Encode.Options(prettyPrint: pretty, sortKeys: sortKeys)
        var bytes: [UInt8] = []
        var encoder = JSON.Encode.Encoder(options: options)
        do throws(JSON.Encode.Error) {
            try encoder.encode(raw, into: &bytes)
        } catch {
            preconditionFailure(
                "JSON encoding exceeded maximum depth despite non-throwing contract: \(error)"
            )
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    @inlinable
    public func serialize(pretty: Bool = false, sortKeys: Bool = false, as: [UInt8].Type) -> [UInt8]
    {
        let options = JSON.Encode.Options(prettyPrint: pretty, sortKeys: sortKeys)
        var bytes: [UInt8] = []
        var encoder = JSON.Encode.Encoder(options: options)
        do throws(JSON.Encode.Error) {
            try encoder.encode(raw, into: &bytes)
        } catch {
            preconditionFailure(
                "JSON encoding exceeded maximum depth despite non-throwing contract: \(error)"
            )
        }
        return bytes
    }
}

extension JSON {

    @inlinable
    public var count: Int? {
        switch raw {
        case .array(let a): return a.count
        case .object(let o): return o.count
        default: return nil
        }
    }

    @inlinable
    public var isEmpty: Bool? {
        switch raw {
        case .array(let a): return a.isEmpty
        case .object(let o): return o.isEmpty
        default: return nil
        }
    }
}
