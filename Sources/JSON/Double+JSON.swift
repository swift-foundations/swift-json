extension Double {

    @inlinable
    public init?(_ json: JSON) {
        guard case .number(let n) = json.raw else { return nil }
        self = n.double
    }
}

extension Float {

    @inlinable
    public init?(_ json: JSON) {
        guard case .number(let n) = json.raw else { return nil }
        self = Float(n.double)
    }
}
