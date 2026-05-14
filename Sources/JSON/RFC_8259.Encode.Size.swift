/// RFC_8259.Encode.Size.swift
/// swift-json
///
/// Size estimation for buffer preallocation.
///
/// Relocated to swift-json (L3) under Arc 1.5 — encoding is
/// implementation, not RFC 8259 spec.

public import RFC_8259

extension RFC_8259.Encode {
    /// Estimates serialized size for buffer preallocation.
    public struct Size: Sendable {
        public let value: RFC_8259.Value

        @usableFromInline
        internal init(_ value: RFC_8259.Value) {
            self.value = value
        }
    }
}

extension RFC_8259.Encode.Size {
    /// Returns estimated byte count.
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
            // quotes + string length + ~12% for escapes
            return s.utf8.count + 2 + (s.utf8.count / 8)
        case .array(let a):
            // brackets + elements + commas
            var size = 2
            for element in a {
                size += estimate(element) + 1
            }
            return size
        case .object(let o):
            // braces + keys + colons + values + commas
            var size = 2
            for (key, val) in o {
                size += key.utf8.count + 3 + estimate(val) + 1
            }
            return size
        }
    }
}
