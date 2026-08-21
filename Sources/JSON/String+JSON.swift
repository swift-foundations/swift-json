extension String {

    @inlinable
    public init(_ json: JSON) {
        if case .string(let value) = json.raw {
            self = value
        } else {
            self = ""
        }
    }
}

extension String {

    @inlinable
    public init?(_ json: JSON?) {
        guard let json else { return nil }
        guard case .string(let value) = json.raw else { return nil }
        self = value
    }
}
