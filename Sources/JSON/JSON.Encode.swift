public import RFC_8259

extension JSON {

    public enum Encode {}
}

extension JSON.Encode {

    public enum Error: Swift.Error, Sendable, Hashable {

        case depthExceeded(maxDepth: Int)
    }
}

extension JSON.Encode.Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .depthExceeded(let maxDepth):
            return "JSON encoding exceeded maximum depth of \(maxDepth)"
        }
    }
}

extension JSON.Encode {

    @inlinable
    public static func encode(
        _ value: RFC_8259.Value,
        options: JSON.Encode.Options = JSON.Encode.Options()
    ) -> [UInt8] {
        var buffer: [UInt8] = []
        var encoder = Encoder(options: options)
        do throws(JSON.Encode.Error) {
            try encoder.encode(value, into: &buffer)
        } catch {
            preconditionFailure(
                "JSON encoding exceeded maximum depth despite non-throwing contract: \(error)"
            )
        }
        return buffer
    }

    @inlinable
    public static func encode<Buffer: Swift.RangeReplaceableCollection>(
        _ value: RFC_8259.Value,
        into buffer: inout Buffer,
        options: JSON.Encode.Options = JSON.Encode.Options()
    ) where Buffer.Element == UInt8 {
        var encoder = Encoder(options: options)
        do throws(JSON.Encode.Error) {
            try encoder.encode(value, into: &buffer)
        } catch {
            preconditionFailure(
                "JSON encoding exceeded maximum depth despite non-throwing contract: \(error)"
            )
        }
    }
}
