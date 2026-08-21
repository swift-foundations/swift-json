public import Async

extension JSON.ND {

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

extension JSON {

    public enum ND {}
}

extension JSON.ND {

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

            while true {
                do {
                    guard let byte = try await iterator.next() else {

                        done = true
                        if buffer.isEmpty { return nil }
                        defer { buffer.removeAll() }
                        do throws(JSON.Error) {
                            return .success(try JSON.parse(buffer))
                        } catch {
                            return .failure(error)
                        }
                    }

                    if byte == 0x0A {
                        if buffer.isEmpty { continue }
                        defer { buffer.removeAll(keepingCapacity: true) }
                        do throws(JSON.Error) {
                            return .success(try JSON.parse(buffer))
                        } catch {
                            return .failure(error)
                        }
                    }

                    if byte == 0x0D { continue }

                    buffer.append(Byte(byte))
                } catch {

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

extension JSON {

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

extension JSON.Serializable {

    @inlinable
    public init<S: AsyncSequence & Sendable>(
        collecting bytes: S
    ) async throws(JSON.Error)
    where S.Element == UInt8 {
        let json = try await JSON.parse(collecting: bytes)
        self = try Self.deserialize(json)
    }
}

extension JSON.Parse {

    @inlinable
    public func stream<S: AsyncSequence & Sendable>(
        ndjson bytes: S
    ) -> Async.Stream<Result<JSON, JSON.Error>>
    where S.Element == UInt8 {

        Async.Stream {
            let state = JSON.ND.State(bytes.makeAsyncIterator())
            return Async.Stream<Result<JSON, JSON.Error>>.Iterator {
                await state.next()
            }
        }
    }

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
