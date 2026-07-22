import Foundation
import JSON
import Testing

@testable import JSON_Foundation_Integration

extension JSON.Foundation {
    @Suite
    struct Test {
        @Test
        func `default codec preserves Foundation wire format and consumes input`() throws {
            let coder = JSON.Foundation.Coder<[String: String]>()
            var input = Data(#"{"value":"blob"}"#.utf8)

            let value = try coder.parse(&input)

            #expect(value == ["value": "blob"])
            #expect(input.isEmpty)

            var output = Data()
            try coder.serialize(value, into: &output)
            #expect(output == Data(#"{"value":"blob"}"#.utf8))
        }

        @Test
        func `decode failure has the typed owner error`() {
            let coder = JSON.Foundation.Coder<[String: String]>()
            var input = Data("{".utf8)

            do throws(JSON.Foundation.Error) {
                _ = try coder.parse(&input)
                Issue.record("Expected malformed JSON to fail")
            } catch {
                #expect(error == .decoding)
            }
        }

        @Test
        func `encode failure has the typed owner error`() {
            let coder = JSON.Foundation.Coder<Double>()
            var output = Data()

            do throws(JSON.Foundation.Error) {
                try coder.serialize(.nan, into: &output)
                Issue.record("Expected nonconforming floating-point value to fail")
            } catch {
                #expect(error == .encoding)
            }
        }
    }
}
