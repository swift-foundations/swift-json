extension JSON.Decoder {

    internal struct Key {

        internal let stringValue: String

        internal let intValue: Int?
    }
}

extension JSON.Decoder.Key: CodingKey {

    internal init?(stringValue: String) {
        self.init(stringValue: stringValue, intValue: nil)
    }

    internal init?(intValue: Int) {
        self.init(stringValue: "\(intValue)", intValue: intValue)
    }
}

extension JSON.Decoder.Key {

    internal static let `super` = JSON.Decoder.Key(
        stringValue: "super",
        intValue: nil
    )

    internal static func index(_ index: Int) -> JSON.Decoder.Key {
        JSON.Decoder.Key(stringValue: "\(index)", intValue: index)
    }
}
