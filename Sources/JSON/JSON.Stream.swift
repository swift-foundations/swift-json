/// JSON.Stream.swift
/// swift-json
///
/// Async streaming JSON APIs
///
/// This module provides streaming parsers for JSON data, supporting:
/// - NDJSON (newline-delimited JSON) from async sequences
/// - Single document collection from async sequences
///
/// ## Streaming Architecture
///
/// JSON parsing requires some lookahead (e.g., distinguishing `{` from `[`),
/// which means it cannot operate on pure
/// `Parsing.Input_Primitives.Input.Streaming` sources.
/// However, the async streaming APIs in this module work with `AsyncSequence`
/// and buffer minimally:
///
/// - NDJSON: Buffers one line at a time
/// - Single document: Collects entire input (necessary for full JSON parsing)
///
/// For memory-constrained environments parsing large documents, consider
/// using a SAX-style parser or splitting input into smaller documents.

public import Async

// MARK: - NDJSON Streaming

extension JSON.ND {
    /// Creates a stream of JSON values from newline-delimited input.
    ///
    /// Each line is parsed as a complete JSON value. Empty lines are skipped.
    /// Parse errors are returned as `.failure` results, allowing the stream
    /// to continue processing subsequent lines.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let byteStream: some AsyncSequence<UInt8, Never> = ...
    ///
    /// for await result in JSON.ND.stream(byteStream) {
    ///     switch result {
    ///     case .success(let json):
    ///         print(Int(json.id))
    ///     case .failure(let error):
    ///         print("Parse error: \(error)")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter bytes: An async sequence of UTF-8 bytes.
    /// - Returns: A stream of parse results, one per line.
    @inlinable
    public static func stream<S: AsyncSequence & Sendable>(
        _ bytes: S
    ) -> Async.Stream<Result<JSON, JSON.Error>>
    where S.Element == UInt8 {
        Async.Stream {
            let state = State(bytes.makeAsyncIterator())
            return Async.Stream<Result<JSON, JSON.Error>>.Iterator {
                await state.next()
            }
        }
    }
}

// MARK: - Newline-Delimited JSON (NDJSON)

extension JSON {
    /// Namespace for newline-delimited JSON (NDJSON) parsing infrastructure.
    ///
    /// "ND" stands for "Newline-Delimited", the format where each line
    /// contains a complete JSON value.
    public enum ND {}
}

extension JSON.ND {
    // WHY: Category D — structural Sendable workaround.
    // WHY: AsyncIteratorProtocol generic parameter blocks Sendable inference.
    // WHY: No caller invariant to uphold — data is structurally safe.
    // WHEN TO REMOVE: When compiler gains structural Sendable inference through
    // WHEN TO REMOVE: AsyncIteratorProtocol generic parameters.
    // TRACKING: unsafe-audit-findings.md Category D; SP-4.
    /// Internal state machine for NDJSON parsing.
    @usableFromInline
    internal final class State<I: AsyncIteratorProtocol>: @unchecked Sendable
    where I.Element == UInt8 {
        @usableFromInline
        var iterator: I

        @usableFromInline
        var buffer: [Byte] = []

        @usableFromInline
        var done = false

        @usableFromInline
        init(_ iterator: I) {
            self.iterator = iterator
        }

        @usableFromInline
        func next() async -> Result<JSON, JSON.Error>? {
            guard !done else { return nil }

            // Accumulate bytes until newline or end of input
            while true {
                do {
                    guard let byte = try await iterator.next() else {
                        // End of input - parse remaining buffer
                        done = true
                        if buffer.isEmpty { return nil }
                        defer { buffer.removeAll() }
                        do throws(JSON.Error) {
                            return .success(try JSON.parse(buffer))
                        } catch {
                            return .failure(error)
                        }
                    }

                    if byte == 0x0A {  // newline
                        if buffer.isEmpty { continue }  // skip empty lines
                        defer { buffer.removeAll(keepingCapacity: true) }
                        do throws(JSON.Error) {
                            return .success(try JSON.parse(buffer))
                        } catch {
                            return .failure(error)
                        }
                    }

                    // Skip carriage return (handle \r\n)
                    if byte == 0x0D { continue }

                    buffer.append(Byte(byte))
                } catch {
                    // Iterator threw - treat as end of stream
                    done = true
                    if buffer.isEmpty { return nil }
                    defer { buffer.removeAll() }
                    do throws(JSON.Error) {
                        return .success(try JSON.parse(buffer))
                    } catch {
                        return .failure(error)
                    }
                }
            }
        }
    }
}

// MARK: - Single Document Async Parse

extension JSON {
    /// Parses a single JSON document from an async byte source.
    ///
    /// Collects all bytes from the source, then parses them as a single JSON
    /// document. For streaming multiple JSON values, use `stream(ndjson:)`.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let json = try await JSON.parse(collecting: byteStream)
    /// print(json.name.string)
    /// ```
    ///
    /// - Parameter bytes: An async sequence of UTF-8 bytes.
    /// - Returns: The parsed JSON value.
    /// - Throws: `JSON.Error` if parsing fails.
    @inlinable
    public static func parse<S: AsyncSequence & Sendable>(
        collecting bytes: S
    ) async throws(JSON.Error) -> JSON
    where S.Element == UInt8 {
        var buffer: [Byte] = []
        do {
            for try await byte in bytes {
                buffer.append(Byte(byte))
            }
        } catch {
            throw .unknown
        }
        return try JSON.parse(buffer)
    }
}

// MARK: - JSON.Serializable Async Extensions

extension JSON.Serializable {
    /// Creates an instance by collecting and parsing JSON from an async byte source.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let user: User = try await .init(collecting: byteStream)
    /// ```
    ///
    /// - Parameter bytes: An async sequence of UTF-8 bytes.
    /// - Throws: `JSON.Error` if parsing or deserialization fails.
    @inlinable
    public init<S: AsyncSequence & Sendable>(
        collecting bytes: S
    ) async throws(JSON.Error)
    where S.Element == UInt8 {
        let json = try await JSON.parse(collecting: bytes)
        self = try Self.deserialize(json)
    }
}

// MARK: - Streaming Support

extension JSON.Parse {
    /// Creates a NDJSON stream parser.
    ///
    /// Returns a parser that processes newline-delimited JSON from async
    /// sequences. Each line is parsed as a complete JSON value.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let stream = JSON.parse.stream(ndjson: byteSequence)
    /// for await result in stream {
    ///     switch result {
    ///     case .success(let json): print(json)
    ///     case .failure(let error): print("Error: \(error)")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter bytes: An async sequence of UTF-8 bytes.
    /// - Returns: A stream of parse results, one per line.
    @inlinable
    public func stream<S: AsyncSequence & Sendable>(
        ndjson bytes: S
    ) -> Async.Stream<Result<JSON, JSON.Error>>
    where S.Element == UInt8 {
        // Delegate to the static stream function
        Async.Stream {
            let state = JSON.ND.State(bytes.makeAsyncIterator())
            return Async.Stream<Result<JSON, JSON.Error>>.Iterator {
                await state.next()
            }
        }
    }

    /// Parses a single JSON document from an async byte source.
    ///
    /// - Parameter bytes: An async sequence of UTF-8 bytes.
    /// - Returns: The parsed JSON value.
    /// - Throws: `JSON.Error` if parsing fails.
    @inlinable
    public func collecting<S: AsyncSequence & Sendable>(
        _ bytes: S
    ) async throws(JSON.Error) -> JSON
    where S.Element == UInt8 {
        var buffer: [Byte] = []
        do {
            for try await byte in bytes {
                buffer.append(Byte(byte))
            }
        } catch {
            throw .unknown
        }
        return try self(buffer)
    }
}
