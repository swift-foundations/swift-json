/// Extensions for converting JSON values to Int.

// MARK: - Int from JSON

extension Int {
    /// Creates an integer from a JSON number value.
    ///
    /// Returns `nil` if the JSON value is not a number,
    /// or if the number cannot be represented as an Int.
    ///
    /// - Parameter json: The JSON value.
    @inlinable
    public init?(_ json: JSON) {
        guard case .number(let n) = json.raw else { return nil }
        guard let value = n.int64 else { return nil }
        guard value >= Int64(Int.min) && value <= Int64(Int.max) else { return nil }
        self = Int(value)
    }
}

// MARK: - Int64 from JSON

extension Int64 {
    /// Creates a 64-bit integer from a JSON number value.
    ///
    /// Returns `nil` if the JSON value is not a number,
    /// or if the number cannot be represented as an Int64.
    ///
    /// - Parameter json: The JSON value.
    @inlinable
    public init?(_ json: JSON) {
        guard case .number(let n) = json.raw else { return nil }
        guard let value = n.int64 else { return nil }
        self = value
    }
}
