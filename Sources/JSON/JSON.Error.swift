import RFC_8259

extension JSON {

    public enum Error: Swift.Error, Sendable, Hashable {

        case typeMismatch(expected: String, got: String)

        case missingKey(String)

        case invalidSyntax(message: String, location: Text.Location)

        case emptyInput

        case depthExceeded(limit: Int)

        case unknown

        @usableFromInline
        internal init(_ error: RFC_8259.Error) {
            switch error {
            case .unexpectedToken(let pos, _, _):
                self = .invalidSyntax(
                    message: "Unexpected token",
                    location: pos.location
                )

            case .unexpectedEndOfInput(let pos, _):
                if pos.offset == .zero {
                    self = .emptyInput
                } else {
                    self = .invalidSyntax(
                        message: "Unexpected end of input",
                        location: pos.location
                    )
                }

            case .invalidNumber(let pos, let reason):
                self = .invalidSyntax(
                    message: "Invalid number: \(reason)",
                    location: pos.location
                )

            case .invalidString(let pos, let reason):
                self = .invalidSyntax(
                    message: "Invalid string: \(reason)",
                    location: pos.location
                )

            case .invalidUTF8(let pos, _):
                self = .invalidSyntax(
                    message: "Invalid UTF-8 sequence",
                    location: pos.location
                )

            case .depthExceeded(_, let limit):
                self = .depthExceeded(limit: limit)

            case .trailingContent(let pos):
                self = .invalidSyntax(
                    message: "Trailing content after JSON value",
                    location: pos.location
                )
            }
        }
    }
}

extension JSON.Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .typeMismatch(let expected, let got):
            return "Type mismatch: expected \(expected), got \(got)"

        case .missingKey(let key):
            return "Missing required key: '\(key)'"

        case .invalidSyntax(let message, let location):
            return "JSON syntax error at \(location): \(message)"

        case .emptyInput:
            return "Empty input"

        case .depthExceeded(let limit):
            return "Nesting depth exceeded limit of \(limit)"

        case .unknown:
            return "Unknown JSON error"
        }
    }
}
