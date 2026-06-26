/// JSON.Encode.Encoder.swift
/// swift-json
///
/// Internal encoder state and encoding methods.
///
/// Renamed under Arc 1.6 namespace correction: encoding lives at
/// `JSON.*`, not at the L2 spec namespace.

public import RFC_8259
public import ASCII_Primitives

extension JSON.Encode {
    /// Internal encoder state.
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

// MARK: - Encoder Constants

extension JSON.Encode.Encoder {
    // Keywords
    @usableFromInline static let keywordNull: [UInt8] = [.ascii.n, .ascii.u, .ascii.l, .ascii.l]
    @usableFromInline static let keywordTrue: [UInt8] = [.ascii.t, .ascii.r, .ascii.u, .ascii.e]
    @usableFromInline static let keywordFalse: [UInt8] = [.ascii.f, .ascii.a, .ascii.l, .ascii.s, .ascii.e]

    // Escape sequences (static to avoid allocating arrays in hot path)
    @usableFromInline static let escapeQuote: [UInt8] = [.ascii.reverseSlant, .ascii.quotationMark]
    @usableFromInline static let escapeBackslash: [UInt8] = [.ascii.reverseSlant, .ascii.reverseSlant]
    @usableFromInline static let escapeSlash: [UInt8] = [.ascii.reverseSlant, .ascii.solidus]
    @usableFromInline static let escapeBackspace: [UInt8] = [.ascii.reverseSlant, .ascii.b]
    @usableFromInline static let escapeFormfeed: [UInt8] = [.ascii.reverseSlant, .ascii.f]
    @usableFromInline static let escapeNewline: [UInt8] = [.ascii.reverseSlant, .ascii.n]
    @usableFromInline static let escapeCarriageReturn: [UInt8] = [.ascii.reverseSlant, .ascii.r]
    @usableFromInline static let escapeTab: [UInt8] = [.ascii.reverseSlant, .ascii.t]
    @usableFromInline static let escapeUnicodePrefix: [UInt8] = [.ascii.reverseSlant, .ascii.u]

    // Pre-computed indent strings for common depths (default 2-space indent)
    @usableFromInline static let indent1: [UInt8] = Swift.Array("  ".utf8)
    @usableFromInline static let indent2: [UInt8] = Swift.Array("    ".utf8)
    @usableFromInline static let indent3: [UInt8] = Swift.Array("      ".utf8)
    @usableFromInline static let indent4: [UInt8] = Swift.Array("        ".utf8)
    @usableFromInline static let indent5: [UInt8] = Swift.Array("          ".utf8)
    @usableFromInline static let indent6: [UInt8] = Swift.Array("            ".utf8)
    @usableFromInline static let indent7: [UInt8] = Swift.Array("              ".utf8)
    @usableFromInline static let indent8: [UInt8] = Swift.Array("                ".utf8)
}

// MARK: - Encoder Methods

extension JSON.Encode.Encoder {
    /// Encodes a value into the buffer.
    ///
    /// Throws ``JSON/Encode/Error/depthExceeded(maxDepth:)`` when
    /// nesting exceeds ``JSON/Encode/Options/maxDepth``.
    @inlinable
    mutating func encode<Buffer: Swift.RangeReplaceableCollection>(
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
            // Use original bytes for lossless round-trip. Buffer is
            // UInt8-typed (encoder output is byte-stream payload to
            // network/file consumers); Number.Original.bytes is Byte-
            // typed. Lazy `.underlying` projects without allocation.
            buffer.append(contentsOf: n.original.bytes.lazy.map(\.underlying))

        case .string(let s):
            encodeString(s, into: &buffer)

        case .array(let a):
            try encodeArray(a, into: &buffer)

        case .object(let o):
            try encodeObject(o, into: &buffer)
        }
    }

    /// Encodes a string with proper escaping.
    ///
    /// Uses a mark-and-sweep pattern: accumulates bytes between escapes,
    /// bulk-copies safe ranges, processes escapes individually.
    @inlinable
    mutating func encodeString<Buffer: Swift.RangeReplaceableCollection>(
        _ string: String,
        into buffer: inout Buffer
    ) where Buffer.Element == UInt8 {
        buffer.append(.ascii.quotationMark) // "

        var mutableString = string
        mutableString.withUTF8 { utf8 in
            unsafe _escapeUTF8(utf8, escapeSlashes: options.escapeSlashes, into: &buffer)
        }

        buffer.append(.ascii.quotationMark) // "
    }

    /// Scans UTF-8 bytes, bulk-copies safe ranges and emits escape sequences.
    ///
    /// Marked `@unsafe` because the entire body is pointer arithmetic;
    /// each unsafe expression is annotated individually.
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
            case 0x22: // "
                unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
                buffer.append(contentsOf: Self.escapeQuote)
                unsafe cursor += 1
                unsafe mark = cursor
            case 0x5C: // \
                unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
                buffer.append(contentsOf: Self.escapeBackslash)
                unsafe cursor += 1
                unsafe mark = cursor
            case 0x2F where escapeSlashes: // /
                unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
                buffer.append(contentsOf: Self.escapeSlash)
                unsafe cursor += 1
                unsafe mark = cursor
            case 0x08: // backspace
                unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
                buffer.append(contentsOf: Self.escapeBackspace)
                unsafe cursor += 1
                unsafe mark = cursor
            case 0x0C: // formfeed
                unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
                buffer.append(contentsOf: Self.escapeFormfeed)
                unsafe cursor += 1
                unsafe mark = cursor
            case 0x0A: // newline
                unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
                buffer.append(contentsOf: Self.escapeNewline)
                unsafe cursor += 1
                unsafe mark = cursor
            case 0x0D: // carriage return
                unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
                buffer.append(contentsOf: Self.escapeCarriageReturn)
                unsafe cursor += 1
                unsafe mark = cursor
            case 0x09: // tab
                unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
                buffer.append(contentsOf: Self.escapeTab)
                unsafe cursor += 1
                unsafe mark = cursor
            case 0x00...0x1F: // other control chars → \uXXXX
                unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
                buffer.append(contentsOf: Self.escapeUnicodePrefix)
                unsafe encodeHex(UInt16(cursor.pointee), into: &buffer)
                unsafe cursor += 1
                unsafe mark = cursor
            default:
                unsafe cursor += 1 // accumulate
            }
        }

        // Write remaining safe bytes
        unsafe _appendSafe(from: mark, to: cursor, into: &buffer)
    }

    /// Appends bytes from mark to cursor (bulk copy of safe range).
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

    /// Encodes a 16-bit value as 4 hex digits.
    @inlinable
    func encodeHex<Buffer: Swift.RangeReplaceableCollection>(
        _ value: UInt16,
        into buffer: inout Buffer
    ) where Buffer.Element == UInt8 {
        // Per-nibble delegation to the L1 single-byte ASCII primitive
        // preserves the fixed-4 zero-padded \uXXXX output (each masked
        // nibble is 0-15, so each lookup yields exactly one lowercase
        // hex byte and the force-unwrap is structurally non-nil).
        // `hexDigitLowercase` now returns `ASCII.Code?` after the L1
        // retype; `.underlying` recovers the raw `UInt8` for the byte
        // buffer, keeping the emitted bytes identical.
        buffer.append(ASCII.Serialization.hexDigitLowercase(UInt8((value >> 12) & 0x0F))!.underlying)
        buffer.append(ASCII.Serialization.hexDigitLowercase(UInt8((value >> 8) & 0x0F))!.underlying)
        buffer.append(ASCII.Serialization.hexDigitLowercase(UInt8((value >> 4) & 0x0F))!.underlying)
        buffer.append(ASCII.Serialization.hexDigitLowercase(UInt8(value & 0x0F))!.underlying)
    }

    /// Encodes an array.
    @inlinable
    mutating func encodeArray<Buffer: Swift.RangeReplaceableCollection>(
        _ array: RFC_8259.Array,
        into buffer: inout Buffer
    ) throws(JSON.Encode.Error) where Buffer.Element == UInt8 {
        buffer.append(.ascii.leftBracket) // [

        guard depth < options.maxDepth else {
            throw .depthExceeded(maxDepth: options.maxDepth)
        }
        depth += 1

        var first = true
        for element in array {
            if !first {
                buffer.append(.ascii.comma) // ,
            }
            first = false

            if options.prettyPrint {
                buffer.append(.ascii.lf) // newline
                appendIndent(into: &buffer)
            }

            try encode(element, into: &buffer)
        }

        depth -= 1

        if !array.isEmpty && options.prettyPrint {
            buffer.append(.ascii.lf) // newline
            appendIndent(into: &buffer)
        }

        buffer.append(.ascii.rightBracket) // ]
    }

    /// Encodes an object.
    @inlinable
    mutating func encodeObject<Buffer: Swift.RangeReplaceableCollection>(
        _ object: RFC_8259.Object,
        into buffer: inout Buffer
    ) throws(JSON.Encode.Error) where Buffer.Element == UInt8 {
        buffer.append(.ascii.leftBrace) // {

        guard depth < options.maxDepth else {
            throw .depthExceeded(maxDepth: options.maxDepth)
        }
        depth += 1

        var first = true

        if options.sortKeys {
            // Sort by UTF-8 bytes (lexicographic), not Unicode collation
            for (key, value) in object.sorted(by: { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }) {
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
            // Direct iteration - no Array copy
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

        buffer.append(.ascii.rightBrace) // }
    }

    /// Appends indentation for the current depth.
    ///
    /// Uses pre-computed indent strings for the common case (2-space indent, depth <= 8).
    @inlinable
    func appendIndent<Buffer: Swift.RangeReplaceableCollection>(
        into buffer: inout Buffer
    ) where Buffer.Element == UInt8 {
        // Fast path for default 2-space indent
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
                // Deep nesting: fall through to loop
                break
            }
            if depth <= 8 { return }
        }
        // Fallback for custom indent or deep nesting
        for _ in 0..<depth {
            buffer.append(contentsOf: indent)
        }
    }
}
