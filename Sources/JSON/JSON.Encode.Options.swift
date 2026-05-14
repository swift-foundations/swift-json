/// JSON.Encode.Options.swift
/// swift-json
///
/// Options for JSON encoding.
///
/// Renamed under Arc 1.6 namespace correction: encoding lives at
/// `JSON.*`, not at the L2 spec namespace.

extension JSON.Encode {
    /// Options for JSON encoding.
    public struct Options: Sendable {
        /// Whether to format with indentation and newlines.
        public var prettyPrint: Bool

        /// Whether to sort object keys alphabetically.
        ///
        /// When enabled, keys are sorted by UTF-8 byte order (lexicographic),
        /// which is language-agnostic and matches JCS (JSON Canonicalization Scheme).
        public var sortKeys: Bool

        /// Whether to escape forward slashes (for embedding in HTML).
        public var escapeSlashes: Bool

        /// Indentation string (used when prettyPrint is true).
        public var indent: String

        /// Maximum nesting depth (default 512, matching parser).
        ///
        /// Exceeding this depth triggers a precondition failure.
        public var maxDepth: Int

        /// Creates default encoding options.
        public init(
            prettyPrint: Bool = false,
            sortKeys: Bool = false,
            escapeSlashes: Bool = false,
            indent: String = "  ",
            maxDepth: Int = 512
        ) {
            self.prettyPrint = prettyPrint
            self.sortKeys = sortKeys
            self.escapeSlashes = escapeSlashes
            self.indent = indent
            self.maxDepth = maxDepth
        }
    }
}
