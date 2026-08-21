public import RFC_8259

extension JSON {

    public enum Decode {}
}

extension JSON.Decode {

    @inlinable
    public static func parse<C: Swift.Collection & Sendable>(
        _ bytes: C,
        maxDepth: Int = 512
    ) throws(RFC_8259.Error) -> RFC_8259.Value
    where C.Element == Byte, C.Index: Sendable {
        var parserError: RFC_8259.Error? = nil
        let fastResult: RFC_8259.Value? =
            bytes.withContiguousStorageIfAvailable {
                (buffer: UnsafeBufferPointer<Byte>) -> RFC_8259.Value? in
                let span = unsafe buffer.span
                do {
                    return try Implementation.parse(span, maxDepth: maxDepth)
                } catch let error as RFC_8259.Error {
                    parserError = error
                    return nil
                } catch {
                    parserError = nil
                    return nil
                }
            }
            .flatMap { $0 }
        if let value = fastResult { return value }
        if let err = parserError { throw err }
        let array = Swift.Array(bytes)
        return try array.withUnsafeBufferPointer {
            (buffer: UnsafeBufferPointer<Byte>) throws(RFC_8259.Error) -> RFC_8259.Value in
            try unsafe Implementation.parse(buffer.span, maxDepth: maxDepth)
        }
    }
}

extension JSON.Decode {

    @inlinable
    public static func parse(
        _ string: String,
        maxDepth: Int = 512
    ) throws(RFC_8259.Error) -> RFC_8259.Value {
        let byteArray: [Byte] = string.utf8.map(Byte.init)
        return try parse(byteArray, maxDepth: maxDepth)
    }
}

extension JSON.Decode {

    @inlinable
    public static func parse(
        _ string: Substring,
        maxDepth: Int = 512
    ) throws(RFC_8259.Error) -> RFC_8259.Value {
        let byteArray: [Byte] = string.utf8.map(Byte.init)
        return try parse(byteArray, maxDepth: maxDepth)
    }
}
