extension Bool {

    @inlinable
    public init?(_ json: JSON) {
        guard case .bool(let value) = json.raw else { return nil }
        self = value
    }
}
