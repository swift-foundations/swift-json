import RFC_8259

extension JSON {

    public struct Parse: Sendable {
        @usableFromInline
        internal init() {}

        @usableFromInline
        internal let maxDepth: Int = 512
    }

    public static var parse: Parse { Parse() }
}

extension JSON.Parse {

    @inlinable
    public func callAsFunction(_ string: String) throws(JSON.Error) -> JSON {
        do throws(RFC_8259.Error) {
            let value = try JSON.Decode.parse(string, maxDepth: maxDepth)
            return JSON(value)
        } catch {
            throw JSON.Error(error)
        }
    }

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

extension JSON.Parse {

    @inlinable
    public func prepared(maxDepth: Int = 512) -> JSON.Prepared {
        JSON.Prepared(maxDepth: maxDepth)
    }
}

extension JSON.Parse {

    @inlinable
    public func located(maxDepth: Int = 512) -> JSON.Located {
        JSON.Located(maxDepth: maxDepth)
    }
}

extension JSON {

    public struct Prepared: Sendable {

        public let maxDepth: Int

        @usableFromInline
        internal init(maxDepth: Int) {
            self.maxDepth = maxDepth
        }
    }
}

extension JSON.Prepared {

    @inlinable
    public func parse(_ string: String) throws(JSON.Error) -> JSON {
        do throws(RFC_8259.Error) {
            let value = try JSON.Decode.parse(string, maxDepth: maxDepth)
            return JSON(value)
        } catch {
            throw JSON.Error(error)
        }
    }

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

extension JSON {

    public struct Located: Sendable {

        public let maxDepth: Int

        @usableFromInline
        internal init(maxDepth: Int) {
            self.maxDepth = maxDepth
        }
    }
}

extension JSON.Located {

    @inlinable
    public func parse(_ string: String) throws(Parser.Error.Located<JSON.Error>) -> JSON {
        do throws(RFC_8259.Error) {
            let value = try JSON.Decode.parse(string, maxDepth: maxDepth)
            return JSON(value)
        } catch let error {
            throw Parser.Error.Located<JSON.Error>(JSON.Error(error), at: _offset(of: error))
        }
    }

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
