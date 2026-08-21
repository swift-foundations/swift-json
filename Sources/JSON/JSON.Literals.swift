import RFC_8259

extension JSON: ExpressibleByNilLiteral {
    @inlinable
    public init(nilLiteral: ()) {
        self = .null
    }
}

extension JSON: ExpressibleByBooleanLiteral {
    @inlinable
    public init(booleanLiteral value: Bool) {
        self.raw = .bool(value)
    }
}

extension JSON: ExpressibleByIntegerLiteral {
    @inlinable
    public init(integerLiteral value: Int) {
        self.raw = .number(RFC_8259.Number(value))
    }
}

extension JSON: ExpressibleByFloatLiteral {
    @inlinable
    public init(floatLiteral value: Double) {
        self.raw = .number(RFC_8259.Number(value))
    }
}

extension JSON: ExpressibleByStringLiteral {
    @inlinable
    public init(stringLiteral value: String) {
        self.raw = .string(value)
    }
}

extension JSON: ExpressibleByArrayLiteral {
    @inlinable
    public init(arrayLiteral elements: JSON...) {
        self.raw = .array(RFC_8259.Array(elements.map { $0.raw }))
    }
}

extension JSON: ExpressibleByDictionaryLiteral {
    @inlinable
    public init(dictionaryLiteral elements: (String, JSON)...) {
        self.raw = .object(RFC_8259.Object(elements.map { ($0.0, $0.1.raw) }))
    }
}
