// Extensions for converting JSON values to String.

// MARK: - String from JSON

extension String {
    /// Creates a string from a JSON string value.
    ///
    /// Returns the string value if this is a JSON string,
    /// otherwise returns an empty string.
    ///
    /// - Parameter json: The JSON value.
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
    /// Creates a string from a JSON string value, if available.
    ///
    /// Returns `nil` if the JSON value is not a string or is null.
    ///
    /// - Parameter json: The JSON value.
    @inlinable
    public init?(_ json: JSON?) {
        guard let json = json else { return nil }
        guard case .string(let value) = json.raw else { return nil }
        self = value
    }
}
