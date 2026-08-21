extension Int {

    @inlinable
    public init?(_ json: JSON) {
        guard case .number(let n) = json.raw else { return nil }
        guard let value = n.int64 else { return nil }
        guard value >= Int64(Int.min) && value <= Int64(Int.max) else { return nil }
        self = Int(value)
    }
}

extension Int64 {

    @inlinable
    public init?(_ json: JSON) {
        guard case .number(let n) = json.raw else { return nil }
        guard let value = n.int64 else { return nil }
        self = value
    }
}
