# swift-json

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)

Type-safe JSON values for Swift with typed throws, literal construction, dynamic member navigation, protocol-based serialization, and a pull-driven streaming decoder — all over one RFC 8259 grammar.

---

## Quick Start

```swift
import JSON

// Construct via literals
let payload: JSON = [
    "name": "Grace",
    "age": 52,
    "verified": true,
    "tags": ["swift", "json"]
]

// Serialize
let text = payload.serialize(pretty: true)

// Parse — throws JSON.Error, not `any Error`
let parsed = try JSON.parse(text)

// Navigate with dynamic member lookup; extract with typed initializers
String(parsed.name)       // "Grace" (empty string if not a string)
Int(parsed.age)           // Optional(52)
Bool(parsed.verified)     // Optional(true)
parsed.tags[0]            // JSON value "swift"
parsed.missing.deeply     // .null — navigation never traps
```

Every throwing entry point declares `throws(JSON.Error)`, so `catch` arms match concrete cases without casting.

---

## Installation

Add swift-json to your Package.swift:

```swift
dependencies: [
    .package(url: "https://github.com/swift-foundations/swift-json.git", branch: "main")
]
```

Add the product to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "JSON", package: "swift-json")
    ]
)
```

### Requirements

- Swift 6.2+ (Swift 6 language mode)
- macOS 26.0+, iOS 26.0+, tvOS 26.0+, watchOS 26.0+, visionOS 26.0+

---

## Key Features

- **Typed throws end-to-end** — every parsing and deserialization API throws `JSON.Error`; no `any Error` escapes the surface
- **Literal construction** — `JSON` conforms to all seven `ExpressibleBy*Literal` protocols, so JSON documents read like JSON
- **Non-trapping navigation** — `json.user.name` and `json["items"][0]` return `.null` for missing keys and out-of-bounds indices instead of crashing
- **`JSON.Serializable` protocol** — declare a type's JSON representation once and get `init(json:)`, `init(jsonString:)`, `init(jsonBytes:)`, `jsonString()`, and `jsonBytes()` for free; `String`, `Bool`, `Int`, `Int64`, `Double`, `Array`, `Dictionary`, and `Optional` conform out of the box
- **Event-grain streaming decode** — `JSON.Span.EventStream` is a `~Copyable`, `~Escapable` pull-driven token stream over `Span<Byte>`; conformers can override `deserialize(events:)` to decode bytes-to-target without materializing the value tree, skipping undeclared fields via `skipValue()`
- **Async streaming** — NDJSON line streams and single-document collection from any `AsyncSequence` of bytes
- **RFC 8259 grammar underneath** — parsing, number semantics, and string escapes come from a dedicated RFC 8259 implementation; the `RFC_8259` module is re-exported for advanced use

---

## Serializing Your Own Types

Conform to `JSON.Serializable` to move between your types and JSON without `Codable`:

```swift
import JSON

struct User: JSON.Serializable {
    let name: String
    let age: Int

    static func serialize(_ value: User) -> JSON {
        [
            "name": .string(value.name),
            "age": .number(value.age)
        ]
    }

    static func deserialize(_ json: JSON) throws(JSON.Error) -> User {
        guard let name = String?(json.name) else { throw .missingKey("name") }
        guard let age = Int(json.age) else { throw .missingKey("age") }
        return User(name: name, age: age)
    }
}

let user = try User(jsonString: #"{"name":"Grace","age":52}"#)
let bytes = user.jsonBytes()
```

Conformers that need maximum throughput can additionally override the event-grain hook and decode directly from the token stream:

```swift
let user = try User.from(eventDecodingJsonBytes: bytes)
```

Types that do not override `deserialize(events:)` fall back to the tree-grain path automatically — no conformer is required to change.

---

## Streaming

Newline-delimited JSON (NDJSON) from an async byte source, one `Result` per line so a malformed line does not end the stream:

```swift
import JSON

for await result in JSON.ND.stream(byteStream) {
    switch result {
    case .success(let json):
        print(Int(json.id) ?? 0)
    case .failure(let error):
        print("Skipping malformed line: \(error)")
    }
}
```

Single-document collection from an async byte source:

```swift
let json = try await JSON.parse(collecting: byteStream)
let user: User = try await .init(collecting: byteStream)
```

---

## Architecture

Single module (`JSON`), organized around a small set of key types:

| Type | Purpose |
|------|---------|
| `JSON` | The value type: literals, subscripts, dynamic member lookup, `parse`, `serialize` |
| `JSON.Error` | The typed error thrown by every parsing/deserialization API |
| `JSON.Serializable` | Protocol for your types: tree-grain and event-grain (de)serialization |
| `JSON.Span.EventStream` | Pull-driven token stream over `Span<Byte>` for streaming decode |
| `JSON.Parse` | Parse accessor: `JSON.parse(_:)`, plus prepared and located variants |
| `JSON.Encode` / `JSON.Decode` | Encoding (options: pretty-print, key sorting, slash escaping, max depth) and decoding namespaces |
| `JSON.Coder` | The canonical bidirectional codec for `RFC_8259.Value` |
| `JSON.ND` | Newline-delimited JSON streaming |

Importing `JSON` also re-exports the `RFC_8259` module, so the underlying value, number, and error types are available without a second import.

---

## Error Handling

All throwing APIs throw `JSON.Error`:

```
JSON.Error
├── .typeMismatch(expected: String, got: String)   // Deserialization type mismatch
├── .missingKey(String)                            // Required object key absent
├── .invalidSyntax(message: String, location: Text.Location)  // Malformed JSON, with line + column
├── .emptyInput                                    // Empty or whitespace-only input
├── .depthExceeded(limit: Int)                     // Nesting depth over the limit
└── .unknown                                       // Unclassified failure
```

Typed throws means exhaustive matching without casting:

```swift
do {
    let user = try User(jsonString: input)
} catch .typeMismatch(let expected, let got) {
    print("Expected \(expected), got \(got)")
} catch .missingKey(let key) {
    print("Missing key: \(key)")
} catch .invalidSyntax(let message, let location) {
    print("Syntax error at \(location): \(message)")
} catch .emptyInput {
    print("No input")
} catch .depthExceeded(let limit) {
    print("Deeper than \(limit) levels")
} catch .unknown {
    print("Unknown error")
}
```

---

## Community

<!-- BEGIN: discussion -->
*Discussion thread will be created at first public flip.*
<!-- END: discussion -->

---

## License

Apache 2.0. See [LICENSE.md](LICENSE.md) for details.
