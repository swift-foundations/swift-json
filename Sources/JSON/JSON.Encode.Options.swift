extension JSON.Encode {

    public struct Options: Sendable {

        public var prettyPrint: Bool

        public var sortKeys: Bool

        public var escapeSlashes: Bool

        public var indent: String

        public var maxDepth: Int

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
