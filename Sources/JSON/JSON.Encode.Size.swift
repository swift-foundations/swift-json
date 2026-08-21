public import RFC_8259

extension JSON.Encode {

    public struct Size: Sendable {
        public let value: RFC_8259.Value

        @usableFromInline
        internal init(_ value: RFC_8259.Value) {
            self.value = value
        }
    }
}

extension JSON.Encode.Size {

    @inlinable
    public func callAsFunction() -> Int {
        estimate(value)
    }

    @usableFromInline
    func estimate(_ value: RFC_8259.Value) -> Int {
        switch value {
        case .null:
            return 4

        case .bool:
            return 5

        case .number(let n):
            return n.original.bytes.count

        case .string(let s):

            return s.utf8.count + 2 + (s.utf8.count / 8)

        case .array(let a):

            var size = 2
            for element in a {
                size += estimate(element) + 1
            }
            return size

        case .object(let o):

            var size = 2
            for (key, val) in o {
                size += key.utf8.count + 3 + estimate(val) + 1
            }
            return size
        }
    }
}
