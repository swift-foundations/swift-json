public import JSON

extension JSON.Foundation {

    public enum Error: Swift.Error, Sendable, Hashable {

        case decoding

        case encoding
    }
}
