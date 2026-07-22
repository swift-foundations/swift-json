public import JSON

extension JSON.Foundation {
    /// A failure produced by Foundation's JSON codec.
    public enum Error: Swift.Error, Sendable, Hashable {
        /// Foundation could not decode the input as the requested value.
        case decoding

        /// Foundation could not encode the value as JSON.
        case encoding
    }
}
