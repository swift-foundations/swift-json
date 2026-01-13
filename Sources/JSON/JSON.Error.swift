/// JSON.Error.swift
/// swift-json
///
/// User-friendly JSON errors

import RFC_8259

extension JSON {
    /// An error that occurred during JSON parsing or deserialization.
    public enum Error: Swift.Error, Sendable, Hashable {
        /// A type mismatch occurred during deserialization.
        case typeMismatch(expected: String, got: String)

        /// A required key was missing from an object.
        case missingKey(String)

        /// The JSON syntax is invalid.
        case invalidSyntax(message: String, line: Int, column: Int)

        /// The input was empty or whitespace-only.
        case emptyInput

        /// Nesting depth exceeded the limit.
        case depthExceeded(limit: Int)

        /// An unknown error occurred.
        case unknown

        /// Creates an error from an RFC 8259 error.
        @usableFromInline
        internal init(_ error: RFC_8259.Error) {
            switch error {
            case .unexpectedToken(let pos, _, _):
                self = .invalidSyntax(
                    message: "Unexpected token",
                    line: pos.line,
                    column: pos.column
                )

            case .unexpectedEndOfInput(let pos, _):
                if pos.offset == 0 {
                    self = .emptyInput
                } else {
                    self = .invalidSyntax(
                        message: "Unexpected end of input",
                        line: pos.line,
                        column: pos.column
                    )
                }

            case .invalidNumber(let pos, let reason):
                self = .invalidSyntax(
                    message: "Invalid number: \(reason)",
                    line: pos.line,
                    column: pos.column
                )

            case .invalidString(let pos, let reason):
                self = .invalidSyntax(
                    message: "Invalid string: \(reason)",
                    line: pos.line,
                    column: pos.column
                )

            case .invalidUTF8(let pos, _):
                self = .invalidSyntax(
                    message: "Invalid UTF-8 sequence",
                    line: pos.line,
                    column: pos.column
                )

            case .depthExceeded(_, let limit):
                self = .depthExceeded(limit: limit)

            case .trailingContent(let pos):
                self = .invalidSyntax(
                    message: "Trailing content after JSON value",
                    line: pos.line,
                    column: pos.column
                )
            }
        }
    }
}

// MARK: - CustomStringConvertible

extension JSON.Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .typeMismatch(let expected, let got):
            return "Type mismatch: expected \(expected), got \(got)"

        case .missingKey(let key):
            return "Missing required key: '\(key)'"

        case .invalidSyntax(let message, let line, let column):
            return "JSON syntax error at line \(line), column \(column): \(message)"

        case .emptyInput:
            return "Empty input"

        case .depthExceeded(let limit):
            return "Nesting depth exceeded limit of \(limit)"

        case .unknown:
            return "Unknown JSON error"
        }
    }
}
