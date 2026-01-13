/// Extensions for converting JSON values to Bool.

// MARK: - Bool from JSON

extension Bool {
    /// Creates a boolean from a JSON boolean value.
    ///
    /// Returns `nil` if the JSON value is not a boolean.
    ///
    /// - Parameter json: The JSON value.
    @inlinable
    public init?(_ json: JSON) {
        guard case .bool(let value) = json.raw else { return nil }
        self = value
    }
}
