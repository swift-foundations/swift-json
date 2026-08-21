public import ASCII_Primitives
public import RFC_8259

extension JSON.Encode {

    @usableFromInline
    internal struct Encoder {
        @usableFromInline
        let options: Options

        @usableFromInline
        let indent: [UInt8]

        @usableFromInline
        var depth: Int

        @usableFromInline
        init(options: Options) {
            self.options = options
            self.indent = Swift.Array(options.indent.utf8)
            self.depth = 0
        }
    }
}

extension JSON.Encode.Encoder {

    @usableFromInline static let keywordNull: [UInt8] = [.ascii.n, .ascii.u, .ascii.l, .ascii.l]
    @usableFromInline static let keywordTrue: [UInt8] = [.ascii.t, .ascii.r, .ascii.u, .ascii.e]
    @usableFromInline static let keywordFalse: [UInt8] = [
        .ascii.f, .ascii.a, .ascii.l, .ascii.s, .ascii.e,
    ]

    @usableFromInline static let escapeQuote: [UInt8] = [.ascii.reverseSlant, .ascii.quotationMark]
    @usableFromInline static let escapeBackslash: [UInt8] = [
        .ascii.reverseSlant, .ascii.reverseSlant,
    ]
    @usableFromInline static let escapeSlash: [UInt8] = [.ascii.reverseSlant, .ascii.solidus]
    @usableFromInline static let escapeBackspace: [UInt8] = [.ascii.reverseSlant, .ascii.b]
    @usableFromInline static let escapeFormfeed: [UInt8] = [.ascii.reverseSlant, .ascii.f]
    @usableFromInline static let escapeNewline: [UInt8] = [.ascii.reverseSlant, .ascii.n]
    @usableFromInline static let escapeCarriageReturn: [UInt8] = [.ascii.reverseSlant, .ascii.r]
    @usableFromInline static let escapeTab: [UInt8] = [.ascii.reverseSlant, .ascii.t]
    @usableFromInline static let escapeUnicodePrefix: [UInt8] = [.ascii.reverseSlant, .ascii.u]

    @usableFromInline static let indent1: [UInt8] = Swift.Array("  ".utf8)
    @usableFromInline static let indent2: [UInt8] = Swift.Array("    ".utf8)
    @usableFromInline static let indent3: [UInt8] = Swift.Array("      ".utf8)
    @usableFromInline static let indent4: [UInt8] = Swift.Array("        ".utf8)
    @usableFromInline static let indent5: [UInt8] = Swift.Array("          ".utf8)
    @usableFromInline static let indent6: [UInt8] = Swift.Array("            ".utf8)
    @usableFromInline static let indent7: [UInt8] = Swift.Array("              ".utf8)
    @usableFromInline static let indent8: [UInt8] = Swift.Array("                ".utf8)
}

extension JSON.Encode.Encoder {

    @inlinable
    package mutating func encode<Buffer: Swift.RangeReplaceableCollection>(
        _ value: RFC_8259.Value,
        into buffer: inout Buffer
    ) throws(JSON.Encode.Error) where Buffer.Element == UInt8 {
        switch value {
        case .null:
            buffer.append(contentsOf: Self.keywordNull)

        case .bool(true):
            buffer.append(contentsOf: Self.keywordTrue)

        case .bool(false):
            buffer.append(contentsOf: Self.keywordFalse)

        case .number(let n):

            buffer.append(contentsOf: n.original.bytes.lazy.map(\.underlying))

        case .string(let s):
            encodeString(s, into: &buffer)

        case .array(let a):
            try encodeArray(a, into: &buffer)

        case .object(let o):
            try encodeObject(o, into: &buffer)
        }
    }

    @inlinable
    package mutating func encodeString<Buffer: Swift.RangeReplaceableCollection>(
        _ string: String,
        into buffer: inout Buffer
    ) where Buffer.Element == UInt8 {
        buffer.append(.ascii.quotationMark)

        var mutableString = string
        mutableString.withUTF8 { utf8 in
            unsafe _escapeUTF8(utf8, escapeSlashes: options.escapeSlashes, into: &buffer)
        }

        buffer.append(.ascii.quotationMark)
    }

    @unsafe
    @usableFromInline
    func _escapeUTF8<Buffer: Swift.RangeReplaceableCollection>(
        _ utf8: UnsafeBufferPointer<UInt8>,
        escapeSlashes: Bool,
        into buffer: inout Buffer
    ) where Buffer.Element == UInt8 {
        guard let base = utf8.baseAddress else { return }
        var cursor = unsafe base
        let end = unsafe base + utf8.count
        var mark = unsafe cursor

        while unsafe cursor < end {
            switch unsafe cursor.pointee {
            case 0x22:
                unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
                buffer.append(contentsOf: Self.escapeQuote)
                unsafe cursor += 1
                unsafe mark = cursor

            case 0x5C:
                unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
                buffer.append(contentsOf: Self.escapeBackslash)
                unsafe cursor += 1
                unsafe mark = cursor

            case 0x2F where escapeSlashes:
                unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
                buffer.append(contentsOf: Self.escapeSlash)
                unsafe cursor += 1
                unsafe mark = cursor

            case 0x08:
                unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
                buffer.append(contentsOf: Self.escapeBackspace)
                unsafe cursor += 1
                unsafe mark = cursor

            case 0x0C:
                unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
                buffer.append(contentsOf: Self.escapeFormfeed)
                unsafe cursor += 1
                unsafe mark = cursor

            case 0x0A:
                unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
                buffer.append(contentsOf: Self.escapeNewline)
                unsafe cursor += 1
                unsafe mark = cursor

            case 0x0D:
                unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
                buffer.append(contentsOf: Self.escapeCarriageReturn)
                unsafe cursor += 1
                unsafe mark = cursor

            case 0x09:
                unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
                buffer.append(contentsOf: Self.escapeTab)
                unsafe cursor += 1
                unsafe mark = cursor

            case 0x00...0x1F:
                unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
                buffer.append(contentsOf: Self.escapeUnicodePrefix)
                unsafe encodeHex(UInt16(cursor.pointee), into: &buffer)
                unsafe cursor += 1
                unsafe mark = cursor

            default:
                unsafe cursor += 1
            }
        }

        unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
    }

    @unsafe
    @usableFromInline
    func _appendSafe<Buffer: Swift.RangeReplaceableCollection>(
        from mark: UnsafePointer<UInt8>,
        to cursor: UnsafePointer<UInt8>,
        into buffer: inout Buffer
    ) where Buffer.Element == UInt8 {
        let count = unsafe cursor - mark
        if count > 0 {
            unsafe buffer.append(contentsOf: UnsafeBufferPointer(start: mark, count: count))
        }
    }

    @inlinable
    package func encodeHex<Buffer: Swift.RangeReplaceableCollection>(
        _ value: UInt16,
        into buffer: inout Buffer
    ) where Buffer.Element == UInt8 {

        buffer.append(ASCII.Hexadecimal.code(UInt8((value >> 12) & 0x0F), case: .lower)!.underlying)
        buffer.append(ASCII.Hexadecimal.code(UInt8((value >> 8) & 0x0F), case: .lower)!.underlying)
        buffer.append(ASCII.Hexadecimal.code(UInt8((value >> 4) & 0x0F), case: .lower)!.underlying)
        buffer.append(ASCII.Hexadecimal.code(UInt8(value & 0x0F), case: .lower)!.underlying)
    }

    @inlinable
    package mutating func encodeArray<Buffer: Swift.RangeReplaceableCollection>(
        _ array: RFC_8259.Array,
        into buffer: inout Buffer
    ) throws(JSON.Encode.Error) where Buffer.Element == UInt8 {
        buffer.append(.ascii.leftBracket)

        guard depth < options.maxDepth else {
            throw .depthExceeded(maxDepth: options.maxDepth)
        }
        depth += 1

        var first = true
        for element in array {
            if !first {
                buffer.append(.ascii.comma)
            }
            first = false

            if options.prettyPrint {
                buffer.append(.ascii.lf)
                appendIndent(into: &buffer)
            }

            try encode(element, into: &buffer)
        }

        depth -= 1

        if !array.isEmpty && options.prettyPrint {
            buffer.append(.ascii.lf)
            appendIndent(into: &buffer)
        }

        buffer.append(.ascii.rightBracket)
    }

    @inlinable
    package mutating func encodeObject<Buffer: Swift.RangeReplaceableCollection>(
        _ object: RFC_8259.Object,
        into buffer: inout Buffer
    ) throws(JSON.Encode.Error) where Buffer.Element == UInt8 {
        buffer.append(.ascii.leftBrace)

        guard depth < options.maxDepth else {
            throw .depthExceeded(maxDepth: options.maxDepth)
        }
        depth += 1

        var first = true

        if options.sortKeys {

            for (key, value) in object.sorted(by: {
                $0.key.utf8.lexicographicallyPrecedes($1.key.utf8)
            }) {
                if !first { buffer.append(.ascii.comma) }
                first = false
                if options.prettyPrint {
                    buffer.append(.ascii.lf)
                    appendIndent(into: &buffer)
                }
                encodeString(key, into: &buffer)
                buffer.append(.ascii.colon)
                if options.prettyPrint { buffer.append(.ascii.sp) }
                try encode(value, into: &buffer)
            }
        } else {

            for (key, value) in object {
                if !first { buffer.append(.ascii.comma) }
                first = false
                if options.prettyPrint {
                    buffer.append(.ascii.lf)
                    appendIndent(into: &buffer)
                }
                encodeString(key, into: &buffer)
                buffer.append(.ascii.colon)
                if options.prettyPrint { buffer.append(.ascii.sp) }
                try encode(value, into: &buffer)
            }
        }

        depth -= 1

        if !object.isEmpty && options.prettyPrint {
            buffer.append(.ascii.lf)
            appendIndent(into: &buffer)
        }

        buffer.append(.ascii.rightBrace)
    }

    @inlinable
    package func appendIndent<Buffer: Swift.RangeReplaceableCollection>(
        into buffer: inout Buffer
    ) where Buffer.Element == UInt8 {

        if indent.count == 2 && indent[0] == .ascii.sp && indent[1] == .ascii.sp {
            switch depth {
            case 0: return
            case 1: buffer.append(contentsOf: Self.indent1)
            case 2: buffer.append(contentsOf: Self.indent2)
            case 3: buffer.append(contentsOf: Self.indent3)
            case 4: buffer.append(contentsOf: Self.indent4)
            case 5: buffer.append(contentsOf: Self.indent5)
            case 6: buffer.append(contentsOf: Self.indent6)
            case 7: buffer.append(contentsOf: Self.indent7)
            case 8: buffer.append(contentsOf: Self.indent8)

            default:

                break
            }
            if depth <= 8 { return }
        }

        for _ in 0..<depth {
            buffer.append(contentsOf: indent)
        }
    }
}
