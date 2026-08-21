import Testing

@testable import JSON

private struct Primitives: Decodable {
    let text: String
    let flag: Bool
    let signed: Int
    let unsigned: UInt
    let fraction: Double
    let absent: String?
    let present: String?
}

private struct Inner: Decodable {
    let value: Int
}

private struct Outer: Decodable {
    let name: String
    let inner: Inner
}

private struct Pair: Decodable {
    let first: Int
    let second: Int
}

private enum Colour: String, Decodable {
    case red
    case green
}

private enum Shape: Decodable {
    case circle(radius: Double)
    case square(side: Double)
}

private struct Age: Decodable {
    let years: Int
}

private enum Year: String, CodingKey {
    case years
}

extension Age {
    fileprivate init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Year.self)
        let years = try container.decode(Int.self, forKey: .years)
        guard years >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .years,
                in: container,
                debugDescription: "Age must not be negative, got \(years)."
            )
        }
        self.years = years
    }
}

private struct Cursor: Decodable {
    let count: Int?
    let indices: [Int]
    let endedEmpty: Bool
}

extension Cursor {
    fileprivate init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.count = container.count
        var indices: [Int] = []
        while !container.isAtEnd {
            indices.append(container.currentIndex)
            _ = try container.decode(Int.self)
        }
        self.indices = indices
        self.endedEmpty = container.isAtEnd
    }
}

private struct Retry: Decodable {
    let before: Int
    let failed: Bool
    let afterFailure: Int
    let text: String
    let afterSuccess: Int
}

extension Retry {
    fileprivate init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.before = container.currentIndex

        self.failed = (try? container.decode(Int.self)) == nil
        self.afterFailure = container.currentIndex
        self.text = try container.decode(String.self)
        self.afterSuccess = container.currentIndex
    }
}

private struct Nested: Decodable {
    let afterFailure: Int
    let value: Int
    let afterSuccess: Int
}

extension Nested {
    fileprivate init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()

        _ = try? container.nestedContainer(keyedBy: Year.self)
        self.afterFailure = container.currentIndex
        self.value = try container.decode(Int.self)
        self.afterSuccess = container.currentIndex
    }
}

private struct Deep: Decodable {
    let afterFailure: Int
    let value: Int
    let afterSuccess: Int
}

extension Deep {
    fileprivate init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()

        _ = try? container.nestedUnkeyedContainer()
        self.afterFailure = container.currentIndex
        self.value = try container.decode(Int.self)
        self.afterSuccess = container.currentIndex
    }
}

private struct Kind: Decodable {
    let library: String?
    let executable: Bool
}

private enum Arm: String, CodingKey {
    case library
    case executable
}

extension Kind {
    fileprivate init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Arm.self)
        if container.contains(.library) {
            self.library = try container.decode([String].self, forKey: .library).first
            self.executable = false
            return
        }
        self.library = nil
        self.executable = container.contains(.executable)
    }
}

private struct Remote: Decodable {
    let urlString: String
}

private struct Location: Decodable {
    let remote: [Remote]?
    let local: [String]?
}

private struct Requirement: Decodable {
    let branch: [String]?
    let exact: [String]?
}

private struct Trait: Decodable {
    let name: String
}

private struct SourceControl: Decodable {
    let identity: String
    let location: Location
    let requirement: Requirement
    let productFilter: [String]?
    let traits: [Trait]?
}

private struct FileSystem: Decodable {
    let identity: String
    let path: String
    let productFilter: [String]?
}

private struct Dependency: Decodable {
    let fileSystem: [FileSystem]?
    let sourceControl: [SourceControl]?
}

private struct Product: Decodable {
    let name: String
    let targets: [String]
}

private struct Target: Decodable {
    let name: String
    let dependencies: [String]?
}

private struct Platform: Decodable {
    let platformName: String
    let version: String
}

private struct Manifest: Decodable {
    let name: String
    let dependencies: [Dependency]
    let products: [Product]
    let targets: [Target]
    let platforms: [Platform]?
}

extension JSON.Decoder {

    fileprivate static func path(of error: DecodingError) -> [String] {
        let context: DecodingError.Context
        switch error {
        case .typeMismatch(_, let found): context = found
        case .valueNotFound(_, let found): context = found
        case .keyNotFound(_, let found): context = found
        case .dataCorrupted(let found): context = found
        @unknown default: return []
        }
        return context.codingPath.map(\.stringValue)
    }
}

extension JSON.Decoder {
    @Suite
    struct Test {

        @Suite
        struct Unit {

            @Test
            func `decodes every primitive the containers expose`() throws {
                let json = try JSON.parse(
                    """
                    {
                      "text": "swift",
                      "flag": true,
                      "signed": -42,
                      "unsigned": 42,
                      "fraction": 1.5,
                      "absent": null,
                      "present": "here"
                    }
                    """
                )
                let value = try json.decode(Primitives.self)
                #expect(value.text == "swift")
                #expect(value.flag == true)
                #expect(value.signed == -42)
                #expect(value.unsigned == 42)
                #expect(value.fraction == 1.5)
                #expect(value.absent == nil)
                #expect(value.present == "here")
            }

            @Test
            func `decodes a bare string through a single-value container`() throws {
                #expect(try JSON.parse(#""solo""#).decode(String.self) == "solo")
            }

            @Test
            func `decodes a bare bool through a single-value container`() throws {
                #expect(try JSON.parse("true").decode(Bool.self) == true)
                #expect(try JSON.parse("false").decode(Bool.self) == false)
            }

            @Test
            func `decodes a non-nil optional through a single-value container`() throws {
                #expect(try JSON.parse("7").decode(Int?.self) == 7)
            }

            @Test
            func `decodes a nil optional through a single-value container`() throws {
                let value = try JSON.parse("null").decode(Int?.self)
                #expect(value == nil)
            }

            @Test
            func `decodes a nested keyed container`() throws {
                let json = try JSON.parse(#"{"name":"outer","inner":{"value":9}}"#)
                let value = try json.decode(Outer.self)
                #expect(value.name == "outer")
                #expect(value.inner.value == 9)
            }

            @Test
            func `ignores object keys the target does not declare`() throws {
                let json = try JSON.parse(
                    #"{"first":1,"second":2,"third":3,"fourth":"ignored"}"#
                )
                let value = try json.decode(Pair.self)
                #expect(value.first == 1)
                #expect(value.second == 2)
            }

            @Test
            func `decodeIfPresent distinguishes absent from null`() throws {
                let absent = try JSON.parse(
                    #"{"text":"a","flag":true,"signed":1,"unsigned":1,"fraction":1.0}"#
                )
                .decode(Primitives.self)
                #expect(absent.absent == nil)
                #expect(absent.present == nil)
            }

            @Test
            func `decodes an array into a synthesized collection`() throws {
                let value = try JSON.parse("[1,2,3]").decode([Int].self)
                #expect(value == [1, 2, 3])
            }

            @Test
            func `decodes nested arrays`() throws {
                let value = try JSON.parse("[[1,2],[3],[]]").decode([[Int]].self)
                #expect(value == [[1, 2], [3], []])
            }

            @Test
            func `decodes a dictionary keyed by string`() throws {
                let value = try JSON.parse(#"{"a":1,"b":2}"#).decode([String: Int].self)
                #expect(value == ["a": 1, "b": 2])
            }

            @Test
            func `decodes a synthesized raw-value enum`() throws {
                #expect(try JSON.parse(#""red""#).decode(Colour.self) == .red)
                #expect(try JSON.parse(#""green""#).decode(Colour.self) == .green)
            }

            @Test
            func `decodes a synthesized enum carrying associated values`() throws {
                let json = try JSON.parse(#"{"circle":{"radius":2.5}}"#)
                let value = try json.decode(Shape.self)
                guard case .circle(let radius) = value else {
                    Issue.record("Expected .circle, got \(value)")
                    return
                }
                #expect(radius == 2.5)
            }

            @Test
            func `reports the cursor state of an unkeyed container`() throws {
                let value = try JSON.parse("[10,20,30]").decode(Cursor.self)
                #expect(value.count == 3)
                #expect(value.indices == [0, 1, 2])
                #expect(value.endedEmpty == true)
            }

            @Test
            func `contains reports true for a key whose value is null`() throws {

                let value = try JSON.parse(#"{"executable":null}"#).decode(Kind.self)
                #expect(value.executable == true)
                #expect(value.library == nil)

                let library = try JSON.parse(#"{"library":["automatic"]}"#)
                    .decode(Kind.self)
                #expect(library.library == "automatic")
                #expect(library.executable == false)
            }
        }

        @Suite
        struct `Edge Case` {

            @Test
            func `missing key reports keyNotFound naming the key`() throws {
                let json = try JSON.parse(#"{"first":1}"#)
                #expect(throws: DecodingError.self) {
                    try json.decode(Pair.self)
                }
                do throws(DecodingError) {
                    _ = try json.decode(Pair.self)
                    Issue.record("Expected a keyNotFound failure")
                } catch {
                    guard case .keyNotFound(let key, _) = error else {
                        Issue.record("Expected keyNotFound, got \(error)")
                        return
                    }
                    #expect(key.stringValue == "second")
                }
            }

            @Test
            func `wrong value type reports typeMismatch`() throws {
                let json = try JSON.parse(#"{"first":1,"second":"two"}"#)
                do throws(DecodingError) {
                    _ = try json.decode(Pair.self)
                    Issue.record("Expected a typeMismatch failure")
                } catch {
                    guard case .typeMismatch = error else {
                        Issue.record("Expected typeMismatch, got \(error)")
                        return
                    }
                    #expect(JSON.Decoder.path(of: error) == ["second"])
                }
            }

            @Test
            func `null where a value is required reports valueNotFound`() throws {
                let json = try JSON.parse(#"{"first":1,"second":null}"#)
                do throws(DecodingError) {
                    _ = try json.decode(Pair.self)
                    Issue.record("Expected a valueNotFound failure")
                } catch {
                    guard case .valueNotFound = error else {
                        Issue.record("Expected valueNotFound, got \(error)")
                        return
                    }
                    #expect(JSON.Decoder.path(of: error) == ["second"])
                }
            }

            @Test
            func `type mismatch inside an array names the failing index`() throws {
                let json = try JSON.parse(#"[1,2,"three",4]"#)
                do throws(DecodingError) {
                    _ = try json.decode([Int].self)
                    Issue.record("Expected a typeMismatch failure")
                } catch {
                    #expect(JSON.Decoder.path(of: error) == ["2"])
                }
            }

            @Test
            func `decoding past the end of an array reports valueNotFound`() throws {
                let json = try JSON.parse("[1,2]")
                do throws(DecodingError) {
                    _ = try json.decode(Pair3.self)
                    Issue.record("Expected a valueNotFound failure")
                } catch {
                    guard case .valueNotFound = error else {
                        Issue.record("Expected valueNotFound, got \(error)")
                        return
                    }
                }
            }

            @Test
            func `a custom initializer's validation surfaces with its coding path`() throws {
                let json = try JSON.parse(#"{"years":-1}"#)
                do throws(DecodingError) {
                    _ = try json.decode(Age.self)
                    Issue.record("Expected a dataCorrupted failure")
                } catch {
                    guard case .dataCorrupted(let context) = error else {
                        Issue.record("Expected dataCorrupted, got \(error)")
                        return
                    }
                    #expect(context.codingPath.map(\.stringValue) == ["years"])
                    #expect(context.debugDescription.contains("negative"))
                }
            }

            @Test
            func `a nested custom failure keeps its full coding path`() throws {
                let json = try JSON.parse(#"{"people":[{"years":3},{"years":-7}]}"#)
                do throws(DecodingError) {
                    _ = try json.decode([String: [Age]].self)
                    Issue.record("Expected a dataCorrupted failure")
                } catch {
                    #expect(JSON.Decoder.path(of: error) == ["people", "1", "years"])
                }
            }

            @Test
            func `an error that is not a DecodingError is preserved underneath`() throws {
                let json = try JSON.parse(#"{"value":1}"#)
                do throws(DecodingError) {
                    _ = try json.decode(Foreign.self)
                    Issue.record("Expected a dataCorrupted failure")
                } catch {
                    guard case .dataCorrupted(let context) = error else {
                        Issue.record("Expected dataCorrupted, got \(error)")
                        return
                    }
                    #expect(context.underlyingError is Foreign.Failure)
                }
            }

            @Test
            func `requesting a keyed container from a non-object fails`() throws {
                let json = try JSON.parse("[1,2]")
                #expect(throws: DecodingError.self) {
                    try json.decode(Pair.self)
                }
            }

            @Test
            func `requesting an unkeyed container from a non-array fails`() throws {
                let json = try JSON.parse(#"{"a":1}"#)
                #expect(throws: DecodingError.self) {
                    try json.decode([Int].self)
                }
            }

            @Test
            func `a failed decode does not consume the array element`() throws {

                let value = try JSON.parse(#"["text"]"#).decode(Retry.self)
                #expect(value.before == 0)
                #expect(value.failed == true)
                #expect(value.afterFailure == 0)
                #expect(value.text == "text")
                #expect(value.afterSuccess == 1)
            }

            @Test
            func `a failed nested keyed container does not consume the element`() throws {
                let value = try JSON.parse("[7]").decode(Nested.self)
                #expect(value.afterFailure == 0)
                #expect(value.value == 7)
                #expect(value.afterSuccess == 1)
            }

            @Test
            func `a failed nested unkeyed container does not consume the element`() throws {
                let value = try JSON.parse("[7]").decode(Deep.self)
                #expect(value.afterFailure == 0)
                #expect(value.value == 7)
                #expect(value.afterSuccess == 1)
            }

            @Test
            func `duplicate object keys resolve to the first occurrence`() throws {

                let json = try JSON.parse(#"{"first":1,"second":2,"first":99}"#)
                let value = try json.decode(Pair.self)
                #expect(value.first == 1)
            }
        }

        @Suite
        struct Numeric {

            @Test
            func `signed boundaries convert exactly`() throws {
                #expect(try JSON.parse("127").decode(Int8.self) == 127)
                #expect(try JSON.parse("-128").decode(Int8.self) == -128)
                #expect(try JSON.parse("32767").decode(Int16.self) == 32767)
                #expect(
                    try JSON.parse("9223372036854775807").decode(Int64.self)
                        == Int64.max
                )
            }

            @Test
            func `unsigned boundaries convert exactly`() throws {
                #expect(try JSON.parse("255").decode(UInt8.self) == 255)
                #expect(try JSON.parse("0").decode(UInt8.self) == 0)
                #expect(
                    try JSON.parse("18446744073709551615").decode(UInt64.self)
                        == UInt64.max
                )
            }

            @Test
            func `an out-of-range magnitude is refused`() throws {
                #expect(throws: DecodingError.self) {
                    try JSON.parse("128").decode(Int8.self)
                }
                #expect(throws: DecodingError.self) {
                    try JSON.parse("256").decode(UInt8.self)
                }
                #expect(throws: DecodingError.self) {
                    try JSON.parse("-129").decode(Int8.self)
                }
            }

            @Test
            func `a negative value is never admitted as unsigned`() throws {
                #expect(throws: DecodingError.self) {
                    try JSON.parse("-1").decode(UInt.self)
                }
                #expect(throws: DecodingError.self) {
                    try JSON.parse("-1").decode(UInt8.self)
                }
                #expect(throws: DecodingError.self) {
                    try JSON.parse("-1").decode(UInt64.self)
                }
            }

            @Test
            func `a fractional value is never truncated into an integer`() throws {
                #expect(throws: DecodingError.self) {
                    try JSON.parse("1.5").decode(Int.self)
                }
                #expect(throws: DecodingError.self) {
                    try JSON.parse("-0.25").decode(Int.self)
                }
            }

            @Test
            func `an integral value written with an exponent decodes as an integer`() throws {

                #expect(try JSON.parse("1e2").decode(Int.self) == 100)
            }

            @Test
            func `floating-point values decode from every numeric arm`() throws {
                #expect(try JSON.parse("1.5").decode(Double.self) == 1.5)
                #expect(try JSON.parse("3").decode(Double.self) == 3.0)
                #expect(try JSON.parse("-2.25").decode(Float.self) == -2.25)
                #expect(try JSON.parse("0.5").decode(Float.self) == 0.5)
            }

            @Test
            func `a finite value too large for Float is refused`() throws {

                #expect(throws: DecodingError.self) {
                    try JSON.parse("1e300").decode(Float.self)
                }
            }

            @Test
            func `a finite negative value too large in magnitude for Float is refused`() throws {
                #expect(throws: DecodingError.self) {
                    try JSON.parse("-1e300").decode(Float.self)
                }
            }

            @Test
            func `the largest finite Float decodes`() throws {
                let value = try JSON.parse("3.4028234663852886e38").decode(Float.self)
                #expect(value.isFinite)
                #expect(value == Float.greatestFiniteMagnitude)
            }

            @Test
            func `finite rounding that stays finite is admitted`() throws {

                let rounded = try JSON.parse("0.1").decode(Float.self)
                #expect(rounded.isFinite)
                #expect(rounded == Float(0.1))

                #expect(try JSON.parse("1e300").decode(Double.self) == 1e300)
            }

            @Test
            func `underflow to zero remains ordinary rounding`() throws {
                let value = try JSON.parse("1e-300").decode(Float.self)
                #expect(value.isFinite)
                #expect(value == 0)
            }

            @Test
            func `strings and booleans are never coerced into numbers`() throws {
                #expect(throws: DecodingError.self) {
                    try JSON.parse(#""12""#).decode(Int.self)
                }
                #expect(throws: DecodingError.self) {
                    try JSON.parse("true").decode(Int.self)
                }
                #expect(throws: DecodingError.self) {
                    try JSON.parse("true").decode(Double.self)
                }
            }

            @Test
            func `numbers are never coerced into strings or booleans`() throws {
                #expect(throws: DecodingError.self) {
                    try JSON.parse("1").decode(Bool.self)
                }
                #expect(throws: DecodingError.self) {
                    try JSON.parse("1").decode(String.self)
                }
            }
        }

        @Suite
        struct Integration {

            @Test
            func `decodes a manifest-shaped document end to end`() throws {
                let json = try JSON.parse(Self.manifest)
                let manifest = try json.decode(Manifest.self)

                #expect(manifest.name == "swift-package-manager")
                #expect(manifest.dependencies.count == 2)

                let mirrored = try #require(manifest.dependencies[0].sourceControl?.first)
                #expect(mirrored.identity == "swift-paths")
                #expect(mirrored.location.local == ["/fixture/checkouts/swift-paths"])
                #expect(mirrored.location.remote == nil)
                #expect(mirrored.requirement.branch == ["main"])
                #expect(mirrored.productFilter == nil)
                #expect(mirrored.traits?.first?.name == "default")
                #expect(manifest.dependencies[0].fileSystem == nil)

                let local = try #require(manifest.dependencies[1].fileSystem?.first)
                #expect(local.identity == "swift-css")
                #expect(local.path == "/fixture/checkouts/swift-css")
                #expect(manifest.dependencies[1].sourceControl == nil)

                #expect(manifest.products.count == 1)
                #expect(manifest.products[0].name == "Package Manager")
                #expect(manifest.products[0].targets == ["Package Manager"])

                #expect(manifest.targets.count == 2)
                #expect(manifest.targets[0].dependencies == ["Paths"])
                #expect(manifest.targets[1].dependencies == nil)

                #expect(manifest.platforms?.count == 1)
                #expect(manifest.platforms?.first?.platformName == "macos")
                #expect(manifest.platforms?.first?.version == "26.0")
            }

            @Test
            func `a mirror-transformed local location decodes`() throws {
                let json = try JSON.parse(
                    """
                    {
                      "identity": "swift-spm-standard",
                      "location": { "local": [ "/fixture/checkouts/swift-spm-standard" ] },
                      "productFilter": null,
                      "requirement": { "branch": [ "main" ] },
                      "traits": [ { "name": "default" } ]
                    }
                    """
                )
                let record = try json.decode(SourceControl.self)
                #expect(record.location.local?.first == "/fixture/checkouts/swift-spm-standard")
                #expect(record.location.remote == nil)
            }

            @Test
            func `a remote location decodes`() throws {
                let json = try JSON.parse(
                    """
                    {
                      "identity": "swift-package-manager",
                      "location": {
                        "remote": [
                          { "urlString": "https://github.com/swift-foundations/swift-package-manager.git" }
                        ]
                      },
                      "productFilter": null,
                      "requirement": { "branch": [ "main" ] },
                      "traits": [ { "name": "default" } ]
                    }
                    """
                )
                let record = try json.decode(SourceControl.self)
                #expect(
                    record.location.remote?.first?.urlString
                        == "https://github.com/swift-foundations/swift-package-manager.git"
                )
                #expect(record.location.local == nil)
            }

            fileprivate static let manifest = """
                {
                  "name": "swift-package-manager",
                  "cLanguageStandard": null,
                  "packageKind": { "root": [ "/fixture/checkouts/swift-package-manager" ] },
                  "toolsVersion": { "_version": "6.3.3" },
                  "dependencies": [
                    {
                      "sourceControl": [
                        {
                          "identity": "swift-paths",
                          "location": { "local": [ "/fixture/checkouts/swift-paths" ] },
                          "productFilter": null,
                          "requirement": { "branch": [ "main" ] },
                          "traits": [ { "name": "default" } ]
                        }
                      ]
                    },
                    {
                      "fileSystem": [
                        {
                          "identity": "swift-css",
                          "path": "/fixture/checkouts/swift-css",
                          "productFilter": null,
                          "traits": [ { "name": "default" } ]
                        }
                      ]
                    }
                  ],
                  "products": [
                    {
                      "name": "Package Manager",
                      "settings": [],
                      "targets": [ "Package Manager" ],
                      "type": { "library": [ "automatic" ] }
                    }
                  ],
                  "targets": [
                    {
                      "name": "Package Manager",
                      "dependencies": [ "Paths" ],
                      "exclude": [],
                      "resources": [],
                      "packageAccess": true
                    },
                    {
                      "name": "Package Manager Tests",
                      "exclude": [],
                      "resources": []
                    }
                  ],
                  "platforms": [
                    { "options": [], "platformName": "macos", "version": "26.0" }
                  ]
                }
                """
        }
    }
}

private struct Pair3: Decodable {
    let a: Int
    let b: Int
    let c: Int
}

extension Pair3 {
    fileprivate init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.a = try container.decode(Int.self)
        self.b = try container.decode(Int.self)
        self.c = try container.decode(Int.self)
    }
}

private struct Foreign: Decodable {}

extension Foreign {
    fileprivate struct Failure: Swift.Error {}

    fileprivate init(from decoder: any Decoder) throws {
        throw Failure()
    }
}
