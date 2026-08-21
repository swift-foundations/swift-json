extension JSON {

    public func decode<T: Swift.Decodable>(
        _ type: T.Type = T.self
    ) throws(Swift.DecodingError) -> T {
        try JSON.Decoder(value: raw, codingPath: []).decoded(type)
    }
}
