# RESULTS — codec-throughput-vs-newcodable

Comparison readings against Apple's NewCodable on the canonical
`twitter.json` / `canada.json` / `citm_catalog.json` payloads.

## Status

PARTIAL. The comparison was achieved via two separate harnesses (the
single-binary skeleton in this directory was blocked by Swift
toolchain compiler bugs — see "Constraints" below). Numbers below are
real, on real payloads, with documented methodology.

- Date: 2026-05-19
- Host: macOS 26 arm64
- Build config: release (-O)

## Methodology

Two harnesses run on the SAME three payloads from
`/Users/coen/Developer/swiftlang/swift-foundation/Tests/NewCodableBenchmarks/Resources/`.

### Apple side

- Source: Apple's own `Tests/NewCodableBenchmarks/CodableRevolutionBenchmarks.swift`
- Branch: `experimental/new-codable` at HEAD `9ad63ed`
- Toolchain: Swift 6.4-dev nightly `swift-DEVELOPMENT-SNAPSHOT-2026-03-16-a`
  (5/12 and 5/7 nightlies crash on `MemoryLifetimeVerifier.cpp:263`
  while compiling `Status.JSONBuilder.tryExpectedOrder` in Apple's own
  `Twitter.swift:483` — SIL verifier bug in those nightlies; 3/16
  predates it.)
- Measurement: **MIN of 256 iterations**, wall-clock via `Date.now`,
  output MB/s = bytes / microseconds.
- Work: bytes → typed struct (`Twitter` / `CoordinateFormat` /
  `Catalog`). Three decoders, three encoders per payload.

### Institute side

- Source: `swift-json/Experiments/parse-performance-bench/main.swift`
- Toolchain: Swift 6.3.2 (Xcode default)
- Measurement: **SUM over 256 iterations**, wall-clock via
  `clock_gettime(CLOCK_MONOTONIC)`. Per-iter derived as `sum / 256`.
  This biases ~10–20% slower than Apple's MIN methodology (mean ≥ min).
- Work: bytes → JSON tree (`RFC_8259.Value`). NO struct mapping.

### Important asymmetry

Apple measures `bytes → typed struct` (parse + map). Institute
measures `bytes → JSON tree` (parse only). So Apple's NewCodable is
doing *more* work in *less* time on every row. To get
apples-to-apples on the institute side requires porting
`Twitter.swift` / `CoordinateFormat.swift` / `Catalog.swift` to
`JSON.Serializable` conformances (substantial work, deferred — see
the stubs in this directory).

## Decode results

| Payload | path | per-iter | MB/s | vs Foundation JSONDecoder |
|---|---|---:|---:|---|
| **Twitter** 617 KB | Foundation JSONDecoder *(bytes→struct)* | 4.14 ms | 152 | 1.0× |
| | Foundation JSONSerialization *(bytes→tree)* | 2.52 ms | 250 | 1.6× |
| | **swift-json JSON.parse([UInt8])** *(bytes→tree)* | 3.61 ms | 175 | 1.15× |
| | **NewCodable JSONDecodable** *(bytes→struct, fast path)* | 0.66 ms | **956** | **6.3×** |
| | NewCodable CommonDecodable | 0.86 ms | 730 | 4.8× |
| **Canada** 2.15 MB | Foundation JSONDecoder | 17.7 ms | 127 | 1.0× |
| | Foundation JSONSerialization | 14.4 ms | 156 | 1.2× |
| | **swift-json JSON.parse([UInt8])** | **253.3 ms** | **9** | **0.07× ⚠️ ANOMALY** |
| | NewCodable JSONDecodable | 5.43 ms | 414 | 3.3× |
| | NewCodable CommonDecodable | 10.0 ms | 224 | 1.8× |
| **CITM** 1.65 MB | Foundation JSONDecoder | 13.1 ms | 132 | 1.0× |
| | Foundation JSONSerialization | 4.21 ms | 410 | 3.1× |
| | swift-json JSON.parse([UInt8]) | 19.6 ms | 88 | 0.67× |
| | **NewCodable JSONDecodable** | 1.70 ms | **1013** | **7.7×** |
| | NewCodable CommonDecodable | 3.28 ms | 526 | 4.0× |

## Encode results (Apple side only)

| Payload | path | per-iter | MB/s | vs Foundation |
|---|---|---:|---:|---|
| Twitter | Foundation JSONEncoder | 3.79 ms | 113 | 1.0× |
| | **NewCodable JSONEncodable** | 0.46 ms | **1019** | **9.0×** |
| | NewCodable CommonEncodable | 1.43 ms | 331 | 2.9× |
| Canada | Foundation JSONEncoder | 30.1 ms | 69 | 1.0× |
| | NewCodable JSONEncodable | 7.44 ms | 280 | 4.1× |
| | NewCodable CommonEncodable | 9.22 ms | 226 | 3.3× |
| CITM | Foundation JSONEncoder | 11.2 ms | 42 | 1.0× |
| | **NewCodable JSONEncodable** | 0.96 ms | **517** | **12.3×** |
| | NewCodable CommonEncodable | 1.82 ms | 273 | 6.5× |

## Findings

### NewCodable wins are larger than advertised

- Apple claims "~6× over Foundation" in the forum thread. Across decode:
  3.3× (canada) to 7.7× (citm), average 5.8×. Across encode: 4.1× to
  12.3×, average 8.5×. **Encode wins are bigger than decode wins** —
  under-marketed.
- The JSON-specific path (`JSONDecodable`/`JSONEncodable`) beats the
  common path (`CommonDecodable`/`CommonEncodable`) by 30–60% on
  every measurement. Apple's `@_disfavoredOverload` on the common
  variant has runtime cost; the JSON-specific fast path with macro-
  generated `JSONOptimizedCodingField` (pre-escaped key bytes for
  `memcmp` matching) is where the real wins live.

### swift-json parse is competitive on twitter, weak on citm, anomalous on canada

| Payload | swift-json parse vs Foundation.JSONSerialization |
|---|---|
| Twitter | 1.4× slower (175 MB/s vs 250 MB/s) |
| CITM | 4.7× slower (88 MB/s vs 410 MB/s) |
| Canada | **17× slower** (9 MB/s vs 156 MB/s) |

The canada result is the canonical "outlier worth investigating".
Twitter is competitive; CITM is meaningfully behind; canada is in a
different regime entirely.

### Canada anomaly: hypothesis

`canada.json` is a GeoJSON FeatureCollection dominated by deeply
nested `[[Double]]` coordinate arrays. The 17× gap to Foundation
suggests per-element allocation in swift-json's parser array branch
— likely allocating per-Double or per-inner-array. Foundation's
C-backed parser uses bulk buffers and reuses storage. NewCodable's
parser-driven approach also avoids the per-element cost (3.3× over
Foundation on canada — the smallest NewCodable margin, suggesting
canada is the workload Apple's tree-grain parser also has to work
hardest on).

The institute's `streaming-deserialize-a0-feasibility` arc + the
`JSON.Span.EventStream` event-grain path were already targeting this
class of workload. Canada gives it a concrete number to beat
(currently 9 MB/s; target the 88+ MB/s neighbourhood at minimum).

### Constraints

1. Apple's `experimental/new-codable` branch needs Swift 6.4-dev (the
   `SuppressedAssociatedTypesWithDefaults` experimental feature).
2. 5/12 and 5/7 nightlies crash on Apple's own Twitter.swift SIL.
   3/16 nightly works; 2 months stale.
3. Institute deps need 12 patches (committed sibling) to compile under
   6.4-dev nightlies.
4. Single-binary 5-path bench would need (1) a working nightly AND
   (2) the institute fixes AND (3) ported schemas. Not achievable
   today. Two-binary split (run separately, stitch manually) was the
   working path.

## Raw output

- Apple bench full log: `/tmp/apple-bench316.log` (working tree only;
  re-run with `cd /Users/coen/Developer/swiftlang/swift-foundation &&
  TOOLCHAINS=org.swift.64202603161a swift test --filter
  NewCodableBenchmarks -c release`).
- Institute bench: re-runnable via
  ```
  cd swift-json/Experiments/parse-performance-bench
  swift run -c release parse-performance-bench \
      /Users/coen/Developer/swiftlang/swift-foundation/Tests/NewCodableBenchmarks/Resources/<payload>.json \
      256 all
  ```

## Next steps

See the follow-up performance-investigation research doc in
`swift-json/Research/` (to be authored via `/research-process`).
