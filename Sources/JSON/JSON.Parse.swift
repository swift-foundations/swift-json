/// JSON.Parse.swift
/// swift-json
///
/// Parse accessor pattern for JSON parsing with compilation support.
///
/// This module provides the nested accessor pattern for JSON parsing,
/// enabling discoverable access to different execution strategies:
///
/// ```swift
/// // Direct parsing (existing API)
/// let json = try JSON.parse(string)
///
/// // Parse accessor pattern
/// let prepared = JSON.parse.prepared()
/// let json = try prepared.parse(string)
/// ```

import RFC_8259

// import Async

// MARK: - Parse Accessor

extension JSON {
    /// Accessor providing parse operation variants.
    ///
    /// The `Parse` struct encapsulates execution strategies for JSON parsing,
    /// enabling discoverability via autocomplete:
    ///
    /// ```swift
    /// JSON.parse.
    ///          ├── prepared()   // Eagerly prepared, thread-safe parser
    ///          ├── located()    // Parse with byte-offset error tracking
    ///          └── callAsFunction()  // Direct parse (default)
    /// ```
    public struct Parse: Sendable {
        @usableFromInline
        internal init() {}

        /// The maximum nesting depth.
        @usableFromInline
        internal let maxDepth: Int = 512
    }

    /// Accessor for parse operation variants.
    ///
    /// Use this to discover and access different execution strategies:
    /// - `parse.prepared()` — thread-safe prepared parser
    /// - `parse.located()` — parse with byte-offset error tracking
    /// - `parse(string)` — direct parse (shorthand)
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Create a prepared parser for server use
    /// let parser = JSON.parse.prepared()
    ///
    /// // Parse multiple documents concurrently
    /// await withTaskGroup(of: JSON.self) { group in
    ///     for data in documents {
    ///         group.addTask { try parser.parse(data) }
    ///     }
    /// }
    /// ```
    public static var parse: Parse { Parse() }
}

// MARK: - Parse callAsFunction

extension JSON.Parse {
    /// Parses JSON from a string.
    ///
    /// - Parameter string: The JSON string to parse.
    /// - Returns: The parsed JSON value.
    /// - Throws: `JSON.Error` if parsing fails.
    @inlinable
    public func callAsFunction(_ string: String) throws(JSON.Error) -> JSON {
        do throws(RFC_8259.Error) {
            let value = try JSON.Decode.parse(string, maxDepth: maxDepth)
            return JSON(value)
        } catch {
            throw JSON.Error(error)
        }
    }

    /// Parses JSON from UTF-8 bytes.
    ///
    /// - Parameter bytes: The UTF-8 encoded JSON bytes.
    /// - Returns: The parsed JSON value.
    /// - Throws: `JSON.Error` if parsing fails.
    @inlinable
    public func callAsFunction<Bytes>(_ bytes: Bytes) throws(JSON.Error) -> JSON
    where Bytes: Swift.Collection<Byte>, Bytes: Sendable, Bytes.Index: Sendable {
        do throws(RFC_8259.Error) {
            let value = try JSON.Decode.parse(bytes, maxDepth: maxDepth)
            return JSON(value)
        } catch {
            throw JSON.Error(error)
        }
    }
}

// MARK: - Prepared Parser

extension JSON.Parse {
    /// Creates an eagerly-prepared, thread-safe parser.
    ///
    /// The returned parser is `Sendable` and can be safely shared across
    /// concurrent tasks. Use this when you need to parse multiple documents
    /// in parallel or cache a parser for reuse.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let parser = JSON.parse.prepared()
    ///
    /// // Safe to use from multiple tasks
    /// Task { try parser.parse(data1) }
    /// Task { try parser.parse(data2) }
    /// ```
    ///
    /// - Parameter maxDepth: Maximum nesting depth (default: 512).
    /// - Returns: A thread-safe prepared parser.
    @inlinable
    public func prepared(maxDepth: Int = 512) -> JSON.Prepared {
        JSON.Prepared(maxDepth: maxDepth)
    }
}

// MARK: - Located Parsing

extension JSON.Parse {
    /// Creates a parser that tracks byte offsets in errors.
    ///
    /// The returned parser wraps errors with `Parser.Error.Located`,
    /// providing precise byte-level position information for diagnostics.
    ///
    /// ## Example
    ///
    /// ```swift
    /// do {
    ///     let json = try JSON.parse.located().parse(bytes)
    /// } catch let error as Parser.Error.Located<JSON.Error> {
    ///     print("Error at byte \(error.offset): \(error.error)")
    /// }
    /// ```
    ///
    /// - Parameter maxDepth: Maximum nesting depth (default: 512).
    /// - Returns: A parser that produces located errors.
    @inlinable
    public func located(maxDepth: Int = 512) -> JSON.Located {
        JSON.Located(maxDepth: maxDepth)
    }
}

// MARK: - Prepared Type

extension JSON {
    /// A thread-safe, prepared JSON parser.
    ///
    /// `Prepared` is `Sendable` and can be safely shared across concurrent
    /// tasks. Create one using `JSON.parse.prepared()`.
    ///
    /// ## Concurrency Safety
    ///
    /// ```swift
    /// let parser = JSON.parse.prepared()
    ///
    /// // Safe: Prepared is Sendable
    /// await withTaskGroup(of: JSON.self) { group in
    ///     for data in documents {
    ///         group.addTask { try parser.parse(data) }
    ///     }
    /// }
    /// ```
    public struct Prepared: Sendable {
        /// Maximum nesting depth.
        public let maxDepth: Int

        @usableFromInline
        internal init(maxDepth: Int) {
            self.maxDepth = maxDepth
        }
    }
}

// MARK: - Prepared parse

extension JSON.Prepared {
    /// Parses JSON from a string.
    ///
    /// - Parameter string: The JSON string to parse.
    /// - Returns: The parsed JSON value.
    /// - Throws: `JSON.Error` if parsing fails.
    @inlinable
    public func parse(_ string: String) throws(JSON.Error) -> JSON {
        do throws(RFC_8259.Error) {
            let value = try JSON.Decode.parse(string, maxDepth: maxDepth)
            return JSON(value)
        } catch {
            throw JSON.Error(error)
        }
    }

    /// Parses JSON from UTF-8 bytes.
    ///
    /// - Parameter bytes: The UTF-8 encoded JSON bytes.
    /// - Returns: The parsed JSON value.
    /// - Throws: `JSON.Error` if parsing fails.
    @inlinable
    public func parse<Bytes>(_ bytes: Bytes) throws(JSON.Error) -> JSON
    where Bytes: Swift.Collection<Byte>, Bytes: Sendable, Bytes.Index: Sendable {
        do throws(RFC_8259.Error) {
            let value = try JSON.Decode.parse(bytes, maxDepth: maxDepth)
            return JSON(value)
        } catch {
            throw JSON.Error(error)
        }
    }
}

// MARK: - Located Type

extension JSON {
    /// A parser that produces errors with byte-offset information.
    ///
    /// `Located` wraps parse errors with their byte offset in the input,
    /// enabling precise error reporting. Create one using `JSON.parse.located()`.
    ///
    /// ## Example
    ///
    /// ```swift
    /// do {
    ///     let json = try JSON.parse.located().parse(bytes)
    /// } catch let error as Parser.Error.Located<JSON.Error> {
    ///     print("Error at byte \(error.offset): \(error.error)")
    /// }
    /// ```
    public struct Located: Sendable {
        /// Maximum nesting depth.
        public let maxDepth: Int

        @usableFromInline
        internal init(maxDepth: Int) {
            self.maxDepth = maxDepth
        }
    }
}

// MARK: - Located parse

extension JSON.Located {
    /// Parses JSON from a string with located errors.
    ///
    /// - Parameter string: The JSON string to parse.
    /// - Returns: The parsed JSON value.
    /// - Throws: `Parser.Error.Located<JSON.Error>` if parsing fails.
    @inlinable
    public func parse(_ string: String) throws(Parser.Error.Located<JSON.Error>) -> JSON {
        do throws(RFC_8259.Error) {
            let value = try JSON.Decode.parse(string, maxDepth: maxDepth)
            return JSON(value)
        } catch let error {
            throw Parser.Error.Located<JSON.Error>(JSON.Error(error), at: _offset(of: error))
        }
    }

    /// Parses JSON from UTF-8 bytes with located errors.
    ///
    /// - Parameter bytes: The UTF-8 encoded JSON bytes.
    /// - Returns: The parsed JSON value.
    /// - Throws: `Parser.Error.Located<JSON.Error>` if parsing fails.
    @inlinable
    public func parse<Bytes>(_ bytes: Bytes) throws(Parser.Error.Located<JSON.Error>) -> JSON
    where Bytes: Swift.Collection<Byte>, Bytes: Sendable, Bytes.Index: Sendable {
        do throws(RFC_8259.Error) {
            let value = try JSON.Decode.parse(bytes, maxDepth: maxDepth)
            return JSON(value)
        } catch let error {
            throw Parser.Error.Located<JSON.Error>(JSON.Error(error), at: _offset(of: error))
        }
    }
}

// MARK: - Internal offset helper

/// Extracts the byte offset from an `RFC_8259.Error` case.
///
/// Module-scope free function (not an extension on the spec error
/// type) — see file header per Arc 1.6 namespace correction: the
/// spec namespace must host SPEC content only.
@usableFromInline
internal func _offset(of error: RFC_8259.Error) -> Text.Position {
    switch error {
    case .unexpectedToken(let pos, _, _): return pos.offset
    case .unexpectedEndOfInput(let pos, _): return pos.offset
    case .invalidNumber(let pos, _): return pos.offset
    case .invalidString(let pos, _): return pos.offset
    case .invalidUTF8(let pos, _): return pos.offset
    case .depthExceeded(let pos, _): return pos.offset
    case .trailingContent(let pos): return pos.offset
    }
}
