/// JSON.Decoder+Value.swift
/// swift-json
///
/// Value extraction and error construction for ``JSON/Decoder``.
///
/// Every primitive a container can be asked for is unwrapped here, so the
/// three containers hold no conversion logic of their own — they locate a
/// child value, build a child decoder, and delegate. That keeps the
/// numeric-conversion rules in one place, stated once and tested once.

import RFC_8259

// MARK: - Error construction

extension JSON.Decoder {
    /// A human-readable name for the JSON value's case.
    internal var kind: String {
        switch value {
        case .null: "null"
        case .bool: "a boolean"
        case .number: "a number"
        case .string: "a string"
        case .array: "an array"
        case .object: "an object"
        }
    }

    /// The error for a value of the wrong shape at this position.
    ///
    /// JSON `null` reports `valueNotFound` rather than `typeMismatch`,
    /// matching the distinction `Swift.DecodingError` draws between a
    /// present-but-wrong value and an explicitly absent one.
    internal func mismatch<T>(_ type: T.Type) -> DecodingError {
        let context = DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "Expected to decode \(type) but found \(kind) instead."
        )
        if case .null = value {
            return .valueNotFound(type, context)
        }
        return .typeMismatch(type, context)
    }

    /// The error for a value of the right shape that cannot be represented.
    internal func corrupt(_ description: String) -> DecodingError {
        .dataCorrupted(
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: description
            )
        )
    }
}

// MARK: - Primitive extraction

extension JSON.Decoder {
    internal func string() throws(DecodingError) -> String {
        guard case .string(let string) = value else { throw mismatch(String.self) }
        return string
    }

    internal func bool() throws(DecodingError) -> Bool {
        guard case .bool(let bool) = value else { throw mismatch(Bool.self) }
        return bool
    }
}

// MARK: - Numeric extraction

extension JSON.Decoder {
    /// Unwraps an integer, refusing every lossy conversion.
    ///
    /// ``RFC_8259/Number`` keeps the arm the parser chose, so the rules can
    /// be stated exactly:
    ///
    /// - `.integer` / `.unsigned` convert through `init?(exactly:)`, which
    ///   rejects both out-of-range magnitudes and negative values requested
    ///   as an unsigned type.
    /// - `.float` is admitted only when the value is finite AND has no
    ///   fractional part — matching ``RFC_8259/Number/int``, so `1e2`
    ///   decodes as `100` while `1.5` is refused rather than truncated.
    /// - Strings and booleans are never coerced; they fail as a mismatch.
    internal func integer<T: FixedWidthInteger>(
        _ type: T.Type
    ) throws(DecodingError) -> T {
        guard case .number(let number) = value else { throw mismatch(type) }
        switch number.parsed {
        case .integer(let signed):
            guard let exact = T(exactly: signed) else { throw overflow(number, type) }
            return exact

        case .unsigned(let unsigned):
            guard let exact = T(exactly: unsigned) else { throw overflow(number, type) }
            return exact

        case .float(let float):
            guard float.isFinite, float == float.rounded() else {
                throw corrupt(
                    "JSON number \(number) is not representable as \(type) "
                        + "without discarding its fractional part."
                )
            }
            guard let exact = T(exactly: float) else { throw overflow(number, type) }
            return exact
        }
    }

    /// Unwraps a floating-point value.
    ///
    /// All three arms convert, because every JSON number is a number the
    /// requested binary floating-point type can approximate. Conversion
    /// follows IEEE 754 round-to-nearest: `Double` cannot hold every
    /// `Int64` beyond 2^53, and `Float` cannot hold every `Double`. That
    /// rounding is a property of the REQUESTED type, not a silent widening
    /// of the JSON value, so it is admitted rather than refused.
    internal func floating<T: BinaryFloatingPoint>(
        _ type: T.Type
    ) throws(DecodingError) -> T {
        guard case .number(let number) = value else { throw mismatch(type) }
        switch number.parsed {
        case .integer(let signed): return T(signed)
        case .unsigned(let unsigned): return T(unsigned)
        case .float(let float): return T(float)
        }
    }

    /// The error for a number outside the requested type's range.
    internal func overflow<T>(
        _ number: RFC_8259.Number,
        _ type: T.Type
    ) -> DecodingError {
        corrupt("JSON number \(number) does not fit in \(type).")
    }
}

// MARK: - Decodable extraction

extension JSON.Decoder {
    /// Drives `type`'s own `init(from:)` against this decoder.
    ///
    /// A custom `init(from:)` may throw anything at all, but the public
    /// entry point promises `DecodingError`. A foreign error is therefore
    /// wrapped as `dataCorrupted` with the original preserved in
    /// `underlyingError` and the coding path recorded — nothing is erased.
    /// Wrapping happens at the innermost decoder, where the coding path is
    /// most precise; outer levels see a `DecodingError` and pass it through
    /// untouched, so an error is never wrapped twice.
    internal func decoded<T: Swift.Decodable>(
        _ type: T.Type
    ) throws(DecodingError) -> T {
        // swift-linter:disable:next do throws for typed catch
        // REASON: [IMPL-075] preserves a KNOWN concrete error type through the
        // catch. Here there is none to preserve — `Decodable.init(from:)` is
        // declared `throws` with no typed form, and normalising that open set
        // into `DecodingError` is this function's entire purpose. A
        // `do throws(DecodingError)` cannot compile around it.
        do {
            return try T(from: self)
        } catch let error as DecodingError {
            throw error
        } catch {
            throw .dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription:
                        "\(type) threw an error that was not a DecodingError; "
                        + "it is preserved as the underlying error.",
                    underlyingError: error
                )
            )
        }
    }
}
