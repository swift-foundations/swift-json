// Extensions for converting JSON values to Double.

// MARK: - Double from JSON

extension Double {
    /// Creates a double from a JSON number value.
    ///
    /// Returns `nil` if the JSON value is not a number.
    ///
    /// - Parameter json: The JSON value.
    @inlinable
    public init?(_ json: JSON) {
        guard case .number(let n) = json.raw else { return nil }
        self = n.double
    }
}

// MARK: - Float from JSON

extension Float {
    /// Creates a float from a JSON number value.
    ///
    /// Returns `nil` if the JSON value is not a number.
    ///
    /// - Parameter json: The JSON value.
    @inlinable
    public init?(_ json: JSON) {
        guard case .number(let n) = json.raw else { return nil }
        self = Float(n.double)
    }
}
