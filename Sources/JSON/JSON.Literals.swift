/// JSON.Literals.swift
/// swift-json
///
/// Literal expressibility for JSON values

import RFC_8259

// MARK: - ExpressibleByNilLiteral

extension JSON: ExpressibleByNilLiteral {
    @inlinable
    public init(nilLiteral: ()) {
        self = .null
    }
}

// MARK: - ExpressibleByBooleanLiteral

extension JSON: ExpressibleByBooleanLiteral {
    @inlinable
    public init(booleanLiteral value: Bool) {
        self.raw = .bool(value)
    }
}

// MARK: - ExpressibleByIntegerLiteral

extension JSON: ExpressibleByIntegerLiteral {
    @inlinable
    public init(integerLiteral value: Int) {
        self.raw = .number(RFC_8259.Number(value))
    }
}

// MARK: - ExpressibleByFloatLiteral

extension JSON: ExpressibleByFloatLiteral {
    @inlinable
    public init(floatLiteral value: Double) {
        self.raw = .number(RFC_8259.Number(value))
    }
}

// MARK: - ExpressibleByStringLiteral

extension JSON: ExpressibleByStringLiteral {
    @inlinable
    public init(stringLiteral value: String) {
        self.raw = .string(value)
    }
}

// MARK: - ExpressibleByArrayLiteral

extension JSON: ExpressibleByArrayLiteral {
    @inlinable
    public init(arrayLiteral elements: JSON...) {
        self.raw = .array(RFC_8259.Array(elements.map { $0.raw }))
    }
}

// MARK: - ExpressibleByDictionaryLiteral

extension JSON: ExpressibleByDictionaryLiteral {
    @inlinable
    public init(dictionaryLiteral elements: (String, JSON)...) {
        self.raw = .object(RFC_8259.Object(elements.map { ($0.0, $0.1.raw) }))
    }
}
