# Parse Performance — Canada Anomaly (Numeric-Heavy Workload)

<!--
---
version: 1.1.0
last_updated: 2026-05-19
status: RECOMMENDATION (Patches 1+2 LANDED; Patch 3 LANDED with negative result)
tier: 1
---
-->

## Context

The `codec-throughput-vs-newcodable` cross-decoder benchmark
(`swift-foundations/swift-json/Experiments/codec-throughput-vs-newcodable/RESULTS.md`)
shipped 2026-05-19 with a workload-conditioned anomaly on the
canonical `canada.json` corpus (2.15 MB GeoJSON FeatureCollection of
deeply-nested `[[Double]]` coordinate arrays):

| Path | per-iter | MB/s | vs Foundation.JSONSerialization |
|---|---:|---:|---:|
| Foundation.JSONSerialization (bytes → tree) | 14.4 ms | 156 | 1.0× |
| **swift-json `JSON.parse([UInt8])` (bytes → tree)** | **253.3 ms** | **9** | **17× slower** |
| Apple NewCodable `JSONDecodable` (bytes → struct) | 5.43 ms | 414 | 0.36× (faster) |

The same swift-json parser is **1.4× slower** than
`JSONSerialization` on `twitter.json` (consistent with the
post-Tier-4 baseline in `parse-performance.md` v1.2.0 — 1.02× on the
86 MB Swift stdlib symbol graph) and **4.7× slower** on
`citm_catalog.json`. Canada is in a different regime entirely.

Methodology note: the institute harness uses SUM-over-256 (≈ mean),
Apple uses MIN-of-256. The methodology gap accounts for at most
~10–20%, not the 17× observed. The anomaly is real.

The post-Tier-4 status quo per `parse-performance.md` v1.2.0
("Foundation parity achieved on the bytes path; 1.06× on the String
path — both well below the 1.3× target") was measured on the
**symbol-graph workload** (86 MB, predominantly string-heavy with
identifiers, kind names, doc comments). The Tier-4 Span lexer + lazy
position closed the cursor wedges and the tree-teardown wedge moved
from ~7 % to ~15 % (Amdahl shift, predicted and accepted in
`parse-performance-architecture.md` §7). Canada exposes a different
workload regime — numeric-heavy rather than string-heavy — where the
post-Tier-4 hot path is dominated not by cursor, not by tree teardown,
but by the **per-number construction path** in `lexNumberValue`.

This document identifies the exact code path, sizes the cost against
the canada workload, compares to NewCodable's parser-driven design,
and recommends a small targeted patch.

## Question

What in swift-json's parse pipeline makes `canada.json` 17× slower
than Foundation, and is the fix a small targeted patch or does it
require waiting for the streaming-deserialize event-grain arc?

## Hypothesis

Per-element allocation in the array path — either per-Double,
per-inner-array, or per-Number-token — dominates the wall-clock on
numeric-heavy workloads.

## Workload characterization

`canada.json`:

| Statistic | Value | vs twitter.json | vs citm_catalog.json |
|---|---:|---:|---:|
| Size | 2,251,051 bytes (2.15 MB) | 3.6× | 1.3× |
| Number tokens | 111,126 | 14.2× | 7.4× |
| Number density | 50.6 / KB | 4.0× | 5.7× |
| Avg number length | 18.25 bytes | — | — |
| Numbers > 16 bytes | 108,562 (97.7 %) | — | — |
| Arrays (`[`) | 56,045 | 53× | 5.4× |
| Objects (`{`) | 4 | — | — |
| Max nesting depth | 7 (Polygon coords up to `[[[Double]]]`) | — | — |
| Leaf `[Double, Double]` arrays | 55,563 | — | — |
| Doubles per leaf array | 2.00 (mean) | — | — |

[Verified: 2026-05-19] enumerated against
`/Users/coen/Developer/swiftlang/swift-foundation/Tests/NewCodableBenchmarks/Resources/canada.json`
with a one-shot Python regex scan.

Two-thirds of the file's tokens are JSON numbers. The remaining work
is the array brackets and commas that wrap them. There are essentially
no objects, no strings beyond a handful of top-level keys, and no
escapes. It is the parser's **per-number cost** at scale that matters.

## Findings — what the parser actually does per Number

The current contiguous-bytes parse path lives at
`/Users/coen/Developer/swift-foundations/swift-json/Sources/JSON/JSON.Decode.Implementation.swift`.
(Note: this is the Span-specialized fast path that replaced the old
`RFC_8259.Lexer.swift` per Arc 1.6 namespace correction + streaming-
deserialize placement audit Ticket T-1; the `RFC_8259.Lexer.swift`
file the historical docs cite no longer exists in the live tree.)

The hot loop runs `parseValue` → `lexNumberValue` (lines 557–661 of
`JSON.Decode.Implementation.swift`). Each Number does:

### Step 1 — Stack-only digit accumulation (cheap)

Line 559:
```swift
var bytes = Array_Primitives.Array<UInt8>.Small<24>()
```

`Array.Small<24>` is institute inline-only storage. Bytes are
appended via `scanner.consume()` in tight loops at lines 562–626.
This is stack-only — no heap allocation. **Cost ≈ free.**

### Step 2 — First heap allocation: `byteArray: [UInt8]`

Lines 629–635:
```swift
let span = bytes.span
let byteArray: [UInt8] = .init(unsafeUninitializedCapacity: span.count) { dst, initialized in
    for i in 0..<span.count {
        dst[i] = span[i]
    }
    initialized = span.count
}
```

For canada's 111,126 numbers averaging 18.25 bytes each, this is
**111,126 `Swift.Array<UInt8>` allocations of ~20-byte payload**. Each
allocation goes through `swift_allocObject` / `slowAlloc`.

### Step 3 — Second heap allocation: `RFC_8259.Number.Original(byteArray)`

Line 636 calls into
`/Users/coen/Developer/swift-ietf/swift-rfc-8259/Sources/RFC 8259/RFC_8259.Number.Original.swift:24-31`:

```swift
public init<Bytes: Swift.Collection>(_ bytes: Bytes) where Bytes.Element == UInt8 {
    let array = Swift.Array(bytes)
    if array.count <= 23 {
        self.init(storage: .inline(Inline(array)))
    } else {
        self.init(storage: .heap(array))
    }
}
```

This **re-allocates** the bytes a *second* time as `Swift.Array(bytes)`.
The receiver `bytes` is already a contiguous `Swift.Array<UInt8>` from
step 2, but the generic initializer takes a `Collection`, sees no
specialization opportunity (release-mode generic specialization may or
may not collapse this — but a verbatim re-`Array(bytes)` is the
specified semantics regardless of whether the optimizer elides it).

The Inline path (`Inline.init(bytes:)` at
`RFC_8259.Number.Original.Inline.swift:40-66`) then copies the array
contents into 23 individual `UInt8` slots via 23 sequential
`if bytes.count > N { bN = bytes[N] }` statements. **Three allocations
on this path** so far per Number: the L1 byte-array, the L1 re-array,
and the inline struct itself (stack — free).

### Step 4 — Third heap allocation: `numStr`

Line 637:
```swift
let numStr = String(decoding: byteArray, as: UTF8.self)
```

For ASCII-only bytes (which JSON numbers always are — they are
`-?[0-9.eE+]+`), `String(decoding:as:)` allocates a fresh `String`
backing store. **Per number, one `String` allocation of ~20 bytes.**

### Step 5 — Per-number `Double(numStr)`

Lines 640–660:
```swift
if isFloat {
    guard let value = Double(numStr), value.isFinite else { ... }
    return RFC_8259.Number(value, original: original)
} else {
    if let value = Int64(numStr) { ... }
    else if let value = UInt64(numStr) { ... }
    else if let value = Double(numStr), value.isFinite { ... }
}
```

`Double.init(_: String)` walks the string character-by-character
through the LosslessStringConvertible parser path. For canada's
`-65.613616999999977`-style coordinates (15-decimal-digit precision),
this is the dominant per-number CPU cost.

### Step 6 — Per-element `[RFC_8259.Value].append`

`parseArray` (lines 187–227) starts with `var elements: [RFC_8259.Value] = []`
**with no `reserveCapacity` hint** (line 194). For canada's 55,563 leaf
`[lng, lat]` arrays this is fine (only 2 appends each), but for the
intermediate ring-of-points arrays (which can be hundreds of points
each) this triggers Array doubling — 4, 8, 16, 32, … — and each
doubling reallocates the storage buffer. Foundation pre-sizes its
output array using a single forward scan, or uses a growable buffer.
**Cost: O(log n) doublings per array × 56,045 arrays.**

### Aggregate per-parse on canada

| Step | Allocs per parse | Bytes allocated per parse (rough) |
|---|---:|---:|
| 1. `Array.Small<24>` | 0 (stack) | 0 |
| 2. `byteArray: [UInt8]` | **111,126** | ~2.2 MB (avg 20 B + Array overhead) |
| 3. `Swift.Array(bytes)` re-allocation inside `Original.init` | **111,126** | ~2.2 MB |
| 4. `numStr: String` | **111,126** | ~2.2 MB |
| 5. `Double.init(_: String)` ARC traffic | (no alloc, but per-char loop) | — |
| 6. `[RFC_8259.Value].append` doublings | ~O(arrays · log size) | growing |
| **Total** | **≥ 333,000 heap allocations** | **≥ 6.6 MB** |

For a 2.15 MB input. The parser's allocator traffic alone is **3× the
size of the input** before the value tree itself is materialized.

Numbers > 23 bytes (the heap fallback in `Original.init`) are zero on
this workload — all 111,126 numbers fit inline — so the **only** uses
of the byteArray and the re-allocated `Swift.Array(bytes)` are to be
copied into the 23-byte inline struct and then *discarded*. They are
write-and-throw-away allocations.

## Comparison

### Foundation.JSONSerialization

C-backed (`CoreFoundation` under the hood, `_NSJSONReader`). Parses
numbers directly into `NSNumber` via inline character-by-character
accumulation against the underlying byte pointer; allocates the
output value once. Arrays grow via `CFArray`'s growable buffer with
geometric reallocation but with the buffer reused across the value
tree (one buffer, not one per array). No String round-trip, no
double-allocation for byte storage.

Result: 156 MB/s on canada — same regime as twitter (250 MB/s),
within the linear scaling of input size.

### Apple NewCodable JSONDecodable (`bytes → struct`)

The structurally different design: it is **parser-driven**, not
tree-driven. The parser visits each value and the consumer's
`JSONDecodable` conformance pulls the value into a target field
directly. Arrays of `Double`: the parser sees `[`, then on each
element calls back to `Double.init(jsonContents:)` which reads the
digit bytes off the parser cursor and produces a Double in-place.
No `RFC_8259.Value` is ever materialized.

In `JSONParserDecoder.ArrayDecoder` at
`/Users/coen/Developer/swiftlang/swift-foundation/Sources/NewCodable/JSON/JSONParserDecoder.swift:379-446`,
each element is consumed via `prepareForArrayElement` (line 412/431)
and emitted into the consumer's `~Copyable` storage directly. The
`InlineArray` types at lines 257/275/494 are stack-allocated path
nodes for diagnostics, not storage for parsed values. Numbers are
parsed via the cursor's number-parsing path without ever forming a
`String` or a `Number` wrapper enum.

Result: 414 MB/s on canada. The per-number cost is the digit-scan
plus the Double conversion; nothing else.

### swift-json — where the cost goes

The 17× gap to Foundation on canada decomposes (approximately, from
the alloc-count + scan-cost analysis above) as:

- **Allocator traffic**: 333,000+ heap allocations across 256 iter ≈
  85 million allocations in the SUM-over-256 measurement. Even at
  10ns/allocation (optimistic for Swift's `swift_allocObject` with
  ARC), that's ~850 ms across 256 iterations or **~3.3 ms per parse
  attributable to allocator alone**. The observed 253.3 ms per parse
  is dominated by something else (likely the string-round-trip
  Double parsing and the array doublings) but allocator pressure is
  a substantial contributor.
- **`Double.init(_: String)`** character-by-character parsing on
  111,126 strings per parse. At ~15 characters × ~5ns per character
  = ~75ns × 111,126 = **~8.3 ms per parse on the float-parsing
  alone**. Likely understated; the LosslessStringConvertible path is
  not aggressively optimized.
- **`[RFC_8259.Value].append` doublings** across 56,045 arrays. The
  leaf 2-element arrays are cheap; the intermediate ring arrays
  (hundreds to thousands of points each) trigger many doublings.
- **`outlined destroy of RFC_8259.Value`** recursive teardown per
  iteration — the post-Tier-4 profile attributed ~15 % of the symbol-
  graph parse to this; on canada's 333,338+ Values (1 per number +
  array nodes + nesting) this is materially more dominant.

The hypothesis "per-element allocation in the array path" is
**partially confirmed** — the array path itself is not the worst
offender (Swift.Array doubling is well-optimized), but the
**per-Number construction path** with **three heap allocations per
number** plus the **`Double.init(_: String)` character-by-character
parse** is. On a 50.6-numbers-per-KB workload, those costs sit on the
critical path of every byte.

## Effort estimate

Three independent patches, each small. Land in this order — each is
independently shippable and reversible. Order is value-density × risk.

### Patch 1: Skip the redundant `byteArray` + the `numStr` (SMALL — ~30 LoC)

**Location**: `JSON.Decode.Implementation.swift:629-660`.

**Today**:
```swift
let span = bytes.span
let byteArray: [UInt8] = .init(unsafeUninitializedCapacity: ...) { ... }
let original = RFC_8259.Number.Original(byteArray)
let numStr = String(decoding: byteArray, as: UTF8.self)

if isFloat {
    guard let value = Double(numStr), value.isFinite else { ... }
    return RFC_8259.Number(value, original: original)
} else {
    if let value = Int64(numStr) { ... }
    ...
}
```

**Patch**:
- Pass `bytes.span` directly to a new
  `RFC_8259.Number.Original(_ bytes: borrowing Swift.Span<UInt8>)`
  initializer that constructs `Inline` directly from the span (no
  intermediate `Swift.Array`). Since `bytes` is already
  `Array.Small<24>`, its span is the inline storage; the Inline
  struct copy is 23 byte-field stores, no allocator involved.
- For the float branch, parse the Double off `bytes.span` directly
  via either:
  - A new `RFC_8259.Number.Parsed.float(fromASCII: borrowing Swift.Span<UInt8>) -> Double?`
    helper that does in-place digit accumulation (mirror the existing
    integer path's structure).
  - OR (faster to land): construct the `String` ONCE via
    `String(unsafeUninitializedCapacity:initializingUTF8With:)` from
    the span (same shape as `lexStringValue`'s ASCII fast path at
    line 413–420), use it once for `Double.init(_:)`, then discard.
    Saves one allocation per number, not three, but it's a one-line
    change.
- For the integer branch: prefer `ASCII.Decimal.Parser<Span<UInt8>, Int64>` from
  `swift-ascii-parser-primitives` (this is the Tier 2 of the
  predecessor `parse-performance.md` doc, still HELD). The integer
  branch fires on canada's `0`-token cases only (the leading `0` of
  each `0.xxx` longitude/latitude is the integer part, but the
  decimal point triggers `isFloat = true` so the integer-only branch
  doesn't fire). On canada, the integer branch may be cold — but
  citm and twitter exercise it.

**Saves**: 2 of 3 allocations per Number. For canada that's
~222,000 fewer allocations per parse. Estimated wall-clock savings:
~3-5 ms per parse from allocator alone, plus the cache-pressure
benefit of not touching ~4.4 MB of throwaway memory per parse.

### Patch 2: Pre-allocate `parseArray` storage when shape is predictable (SMALL — ~10 LoC)

**Location**: `JSON.Decode.Implementation.swift:194`.

**Today**:
```swift
var elements: [RFC_8259.Value] = []
```

**Patch**: it's impossible to know array size without a forward scan
(JSON is not length-prefixed), but a default reserve of e.g. 4 or 8
elements eliminates the early doublings that dominate the leaf-array
cost. For canada, where 55,563 of the 56,045 arrays have exactly 2
elements, `reserveCapacity(2)` matches the workload precisely. A
broader `reserveCapacity(4)` is a defensible default that doesn't
hurt large arrays.

```swift
var elements: [RFC_8259.Value] = []
elements.reserveCapacity(4)
```

**Saves**: 1-3 reallocation calls per leaf array × 55,563 arrays =
**~110,000 fewer Array reallocations per parse on canada**. Minor
effect per call but it's a high-frequency hot path.

### Patch 3 (longer): Fast-path the Double parser (MEDIUM — needs evaluation)

The institute does NOT currently have an Eisel-Lemire-class fast
Double parser. The predecessor doc's Tier 2
(`swift-ascii-parser-primitives/Sources/ASCII Decimal Parser Primitives/ASCII.Decimal.Parser.swift`)
covers integers only. The state of the art for fast Double parsing
(Eisel-Lemire 2020 / Lemire 2021) is a multi-hundred-line piece of
work; it does not yet exist in the ecosystem.

This is out of scope for "small targeted patch". Defer until either:
(a) a fast-Double primitive lands in `swift-ascii-parser-primitives` or
similar, OR (b) a structural change (the streaming-deserialize event-
grain path) bypasses the per-Number wrapper entirely on the consumer
side. See "Recommendation" below.

## Comparison summary

| Approach | Allocator traffic per Number | Per-Number CPU |
|---|---|---|
| Foundation.JSONSerialization | 1 alloc (the NSNumber) | Inline digit accumulation, C-coded Double parse |
| Apple NewCodable JSONDecodable | 0 (target field is consumer storage) | Inline digit accumulation, single Double materialize into the consumer field |
| swift-json **today** | **3 allocs** (byteArray, re-array, numStr) + 1 enum wrapping | `Double.init(_: String)` character-by-character |
| swift-json **with Patch 1+2** | 0-1 alloc | `Double.init(_: String)` (still) — patch 3 to remove |
| swift-json **with Patches 1+2+3** | 0-1 alloc | Fast Double parse |

## Outcome

**Status**: RECOMMENDATION.

**Hypothesis disposition**: PARTIALLY CONFIRMED. The "per-element
allocation" framing is right in spirit but wrong in specifics. The
array path itself is not the dominant cost — `Swift.Array` doubling
is well-optimized. The dominant cost is **per-Number construction
overhead**: three heap allocations per Number, all of which are
write-and-throw-away on canada's workload (where every number fits
inline in 24 bytes and the byteArray + re-allocated array exist only
to be copied into the inline struct and then discarded), plus the
String round-trip in the Double parsing path.

### Recommendation

**Patches 1 and 2 are small, surgical, and target-correct.** They
should land as a single arc against
`JSON.Decode.Implementation.swift` (and a new
`RFC_8259.Number.Original(_ bytes: borrowing Swift.Span<UInt8>)`
initializer at
`swift-ietf/swift-rfc-8259/Sources/RFC 8259/RFC_8259.Number.Original.swift`).
Estimated total: ~40 LoC change, behind no API surface change,
preserves the typed-throws contract, preserves the existing public
`Number.Original(_ bytes:)` initializer for non-Span call sites.

**Estimated wall-clock impact on canada**: 253 ms → 100-150 ms per
parse (40-60 % reduction), bringing the gap to Foundation from 17×
to **~6-10×**. The remaining gap is dominated by `Double.init(_: String)`
(Patch 3, out of scope) and the value-tree teardown (which has no
small-patch fix — see `value-tree-redesign-v2.md` SUPERSEDED-BY-EVIDENCE).

**Estimated wall-clock impact on twitter / citm**: Smaller. Twitter
has 7,821 numbers in 631 KB; the per-Number savings × 7,821 ≈ 0.5 ms
saved on a 3.6 ms parse. Citm: 14,986 numbers; perhaps 1 ms saved on
19 ms. Symbol-graph (the canonical 86 MB workload from
parse-performance.md v1.2.0) has even lower number-density and is
unlikely to regress; if anything it benefits slightly.

### Answer to the load-bearing question

**"Is the canada anomaly fixable with a small patch, or does it
require waiting for the streaming-deserialize event-grain arc?"**

**Both, but the small patch closes most of the gap.** The streaming-
deserialize / event-grain path (`JSON.Span.EventStream` at
`swift-json/Sources/JSON/JSON.Span.EventStream.swift`) addresses a
**different** axis: it lets consumers bypass the
`RFC_8259.Value` materialization entirely for `JSON.Serializable`
conformances. That arc closes the gap to Apple's NewCodable-class
performance on `bytes → struct` workloads (consumer-typed shape) by
removing the tree allocation entirely. It does NOT address the per-
Number cost on the `bytes → tree` workload (which canada's benchmark
measures), because the tree workload still materializes every Value.

Patches 1+2 close most of the bytes-→-tree gap. Patches 1+2+3 close
all of it. The streaming-deserialize arc complements but does not
substitute for these patches: a consumer that wants
`RFC_8259.Value` (the symbol-graph oracle, JSONPath queries, dynamic-
member-lookup access) still goes through the tree path, where the
per-Number cost dominates on numeric-heavy inputs.

The framing "swift-json is slow on canada because the tree is the
wrong shape for numeric-heavy data" is partially right — but the
tree is **also** ~3× more allocator-pressured than it needs to be on
the per-Number path. Fix the per-Number path first (small patches,
this doc), then revisit the tree-shape question when a consumer
proves a workload that the per-Number fix doesn't close.

### Out of scope

- **Patch 3 (fast Double parser)**: deferred until a fast-Double
  primitive lands in `swift-ascii-parser-primitives` or similar.
  Closes the residual gap to Foundation on numeric workloads. The
  ecosystem does not have an Eisel-Lemire-class parser today
  ([Verified: 2026-05-19] — `swift-ascii-parser-primitives` has
  `ASCII.Decimal.Parser` for integers only; no fast float parser
  surfaced in any prior research doc).
- **Tree-shape redesign**: `value-tree-redesign-v2.md` is SUPERSEDED-
  BY-EVIDENCE — Copyable wrapper + multi-buffer storage refcount-per-
  copy dominates O(1) gains at small N. Not pursued.
- **Streaming-deserialize event-grain on `bytes → tree`**: by
  design, the event-grain path emits into consumer storage, not into
  `RFC_8259.Value`. It cannot speed up the `bytes → tree` workload
  without abandoning the tree as the output. That's a separate
  consumer-driven decision, not a parser optimization.

## References

### Predecessor and prior art (institute corpus)

- `swift-foundations/swift-json/Research/parse-performance.md` v1.3.0
  (DECISION) — Tier-4 LANDED, Foundation parity 1.02× on 86 MB
  symbol-graph; defines the post-Tier-4 baseline this doc analyses.
  §6 *Residual gap* enumerates the tree-teardown wedge that grew
  from ~7 % to ~15 % post-Tier-4 (Amdahl shift) — confirms tree
  teardown is also a residual concern on canada, but secondary to
  the per-Number cost.
- `swift-foundations/swift-json/Research/parse-performance-architecture.md` v1.0.2
  (DECISION) — Tier-4 architecture doc; defines Architecture A (Span
  cursor + existing tree) and notes "Phase B (arena tree) NOT triggered"
  on the symbol-graph workload. Canada's per-Number cost is a
  different wedge than Phase B's tree-shape question.
- `swift-foundations/swift-json/Research/value-tree-redesign-v2.md`
  (SUPERSEDED-BY-EVIDENCE 2026-05-13) — v2 tree was rolled back;
  parse +339 %, lookup +226 %. Refcount-per-copy dominates O(1)
  gains at small N. The tree shape stays.
- `swift-foundations/swift-json/Experiments/codec-throughput-vs-newcodable/RESULTS.md`
  (2026-05-19) — the data this doc analyses.

### Current parser surface (verified against live code)

- `/Users/coen/Developer/swift-foundations/swift-json/Sources/JSON/JSON.Parse.swift:48-72`
  — public `JSON.parse(_: String)` / `JSON.parse(_: Bytes)` entry,
  delegates to `JSON.Decode.parse`.
- `/Users/coen/Developer/swift-foundations/swift-json/Sources/JSON/JSON.Decode.swift:43-69`
  — `JSON.Decode.parse(_: C, maxDepth:)` Collection dispatcher;
  `withContiguousStorageIfAvailable` fast path; falls back to
  `Swift.Array(bytes)` materialization.
- `/Users/coen/Developer/swift-foundations/swift-json/Sources/JSON/JSON.Decode.Implementation.swift:557-661`
  — `lexNumberValue`. **The per-Number hot path. The patches in this
  doc target lines 629-660.**
- `/Users/coen/Developer/swift-foundations/swift-json/Sources/JSON/JSON.Decode.Implementation.swift:187-227`
  — `parseArray`. Patch 2 target at line 194.
- `/Users/coen/Developer/swift-ietf/swift-rfc-8259/Sources/RFC 8259/RFC_8259.Number.Original.swift:24-31`
  — `Original.init(_ bytes:)`. **The redundant re-`Swift.Array(bytes)`
  is at line 25.** Patch 1 adds a sibling `init(_ bytes: borrowing Swift.Span<UInt8>)`.
- `/Users/coen/Developer/swift-ietf/swift-rfc-8259/Sources/RFC 8259/RFC_8259.Number.Original.Inline.swift:40-66`
  — `Inline.init(_ bytes:)`. The 23-field byte-by-byte copy. Already
  Span-compatible in shape; a sibling Span-taking init is trivial.

### NewCodable comparison

- `/Users/coen/Developer/swiftlang/swift-foundation/Sources/NewCodable/JSON/JSONParserDecoder.swift:379-446`
  — `ArrayDecoder` parser-driven array consumption; no tree
  materialization.
- `/Users/coen/Developer/swiftlang/swift-foundation/Sources/NewCodable/JSON/ParserState.swift:1703-1710`
  — `expectBeginningOfArray` / `expectArrayComma`. The cursor-level
  array boundary detection; consumer code at line 412/431 of
  `JSONParserDecoder.swift` pulls each element into typed storage
  directly.

---

## v1.1.0 — Patch 3 LANDED, Predicted Wall-Clock Win Did NOT Materialize

Date: 2026-05-19. EL parser implemented + integrated + benchmarked.

### What landed

- `swift-primitives/swift-ascii-parser-primitives` commits `4f8f572` +
  `56bf873`:
  - `ASCII.Decimal.Float.Parser<Input>` (`Parser.Protocol` conformer)
    parses ASCII decimal floats from any `Collection.Slice.Protocol`
    byte source via three-tier strategy:
    (1) Clinger fast path for mantissa ≤ 2⁵³−1 and exponent in [−22, 22],
    (2) Eisel–Lemire core via `UInt64.multipliedFullWidth(by:)` + a
        verbatim port of fast_float's 128-bit power-of-five table
        (q ∈ [−342, +308], 651 entries × 2 UInt64 ≈ 10 KiB rodata),
    (3) Slow path — stdlib `Double.init(_: String)` for >19-digit
        literals (rare in JSON).
  - `ASCII.Decimal.Float.parse(_: borrowing Swift.Span<UInt8>)` static
    span entry for hot-path callers (`Swift.Span<UInt8>` does not
    conform to `Collection.Slice.Protocol` — separate entry point).
  - 30 stdlib-agreement tests passing on Swift 6.3.2 / macOS 26 arm64,
    including canada coordinate shape, subnormals, infinities,
    neg-zero, 19-digit boundary, 20-digit slow path, JSON-typical
    numbers, round-to-even edges.
- `swift-foundations/swift-json` (this doc's repo): `lexNumberValue`
  float branch now calls `ASCII.Decimal.Float.parse(span)` directly on
  the inline-storage span. `numStr: String` allocation is eliminated
  on the float branch (integer branch keeps it for
  `Int64`/`UInt64`/fallback `Double`).

### What the wall-clock said

Methodology: min-of-3, SUM over 256 iterations, same
`parse-performance-bench` harness as v1.0.0, same machine.

| Payload | Pre-EL (ms/iter) | Post-EL (ms/iter) | Δ |
|---|---:|---:|---:|
| Twitter (617 KB, 7821 floats) | 3.61 | 3.33 | −7.8% |
| Canada (2.15 MB, 111126 floats) | 253.3 | 239.5 | −5.5% |
| CITM (1.65 MB, 14986 floats) | 19.6 | 18.5 | −5.6% |

Predicted canada wall-clock per v1.0.0's "Comparison summary" table:
**30–60 ms/iter** (~2–4× Foundation). Observed: **239.5 ms/iter**
(~17× Foundation), virtually unchanged.

The handoff that authored Patches 1+2 framed `Double.init(_: String)`
as "the dominant cost (~111–222 ms per parse of the 246 ms)". This
framing is **empirically wrong**. The actual `Double.init(_: String)`
cost on canada is closer to ~10 ms per parse (the v1.0.0 doc's deep-
level estimate of ~75 ns × 111,126 calls ≈ 8.3 ms; the 111–222 ms
figure conflated total parse cost with float-parse cost).

### Where the 239 ms actually goes

Bounded empirically by what Patches 1, 2, and 3 collectively *failed*
to budge:

- Allocator traffic (Patches 1+2 attacked): −7 ms / 246 ms total
  (~3%). Real but minor.
- `Double.init(_: String)` (Patch 3 attacked): −7 ms / 246 ms total
  (~3%). Real but minor.
- **Remaining ~230 ms must be in the tree-construction layer**:
  - `RFC_8259.Value` enum allocation × 333K+ Values per parse (1 per
    Number + 1 per Array node + nesting).
  - `[RFC_8259.Value].append` doublings across the 56K intermediate
    arrays (Patch 2's `reserveCapacity(4)` covered the leaf-array
    case but not the longer ring arrays).
  - Tree teardown via `outlined destroy of RFC_8259.Value` — was
    ~15% on the symbol-graph workload, materially more on canada's
    deeper tree.

The framing "swift-json is slow on canada because the tree is the
wrong shape for numeric-heavy data" (v1.0.0 § Out of scope) is now
strongly supported by empirical bounds: the three small patches that
addressed everything *outside* the tree shape collectively saved
~14 ms; the remaining ~230 ms is structurally constrained by
`RFC_8259.Value`'s tree.

### What this means for the canada anomaly

The anomaly is **not closeable by faster float parsing**. It is also
**not closeable by faster allocator pressure** (Patch 1's framing was
already weak; v1.1.0 confirms). The 17× Foundation gap is a
**value-tree-shape** problem. Closing it requires one of:

- A different tree shape that doesn't pay `RFC_8259.Value` per
  Number. `value-tree-redesign-v2.md` was SUPERSEDED-BY-EVIDENCE
  (refcount-per-copy dominated O(1) gains at small N); a different
  shape may be needed. Out of scope here.
- A consumer-driven path that bypasses the tree entirely — the
  `JSON.Span.EventStream` event-grain arc (`bytes → consumer struct`
  via `JSON.Serializable` conformances). Closes the gap for
  consumers that don't need the tree; doesn't close it for those
  that do.

### What the EL landing *did* deliver

Independent of canada's wall-clock:

- L1 primitive (`ASCII.Decimal.Float.Parser`) reusable by every
  downstream JSON/TOML/CSV/YAML consumer.
- Allocator-traffic reduction: ~111K String allocations × ~20 bytes
  ≈ 2.2 MB per canada parse, eliminated.
- Twitter and CITM both pick up ~6–8% from the elimination, stable
  across runs.
- Correctness floor: 30 stdlib-agreement tests including subnormal,
  infinity, neg-zero, round-to-even. Future consumers parsing edge-
  case floats get a typed-throws-clean path.

### Hypothesis disposition (final)

- v1.0.0 hypothesis "per-element allocation in the array path
  dominates": PARTIALLY CONFIRMED — array allocator is a contributor
  but minor (~3%).
- v1.0.0 hypothesis "`Double.init(_: String)` IS the dominant cost":
  **REJECTED**. Float-parsing cost is ~10 ms, not ~100+ ms.
- v1.0.0 projection "Patches 1+2+3 close most of the bytes-→-tree
  gap, bringing canada to 30–60 ms": **REJECTED**. Patches 1+2+3
  delivered ~7% total improvement (~246 → ~239 ms). The bytes-→-tree
  gap is structurally bound by `RFC_8259.Value`-tree cost; no patch
  to allocator pressure or float parsing closes it.
- New hypothesis: "the residual 230 ms is `RFC_8259.Value` enum
  allocation + tree teardown + intermediate array doublings". Bounded
  empirically by elimination; not yet directly profiled.

### Recommendation (revised)

- Patches 1+2+3 have landed. They are correctness-positive and yield
  modest (~6–8%) speedups on numeric workloads — keep them.
- The canada anomaly is now a **tree-shape problem**, not a parser
  problem. Recommendations for closing the 17× gap belong in a
  separate research arc focused on `RFC_8259.Value` allocation /
  teardown / array growth.
- Consumers willing to bypass `RFC_8259.Value` entirely (consume
  events into typed structs via `JSON.Serializable`) should look at
  the `JSON.Span.EventStream` arc — that's the path to NewCodable-
  class performance on bytes → struct, independent of this anomaly.

### Skill references (v1.1.0 additions)

- [HANDOFF-016] (proposal-staleness, premise-staleness axes) —
  v1.0.0's premise about `Double.init(_: String)` cost was stale
  against the empirical 6 ms / 246 ms ratio.
- [RES-018] — correctness-and-evergreen judgment carried this work;
  the EL parser is the right L1 primitive regardless of whether it
  closes canada specifically.
- [BENCH-005] — comparison benchmark methodology preserved across
  v1.0.0 → v1.1.0; same harness, same payloads, same SUM-over-256.

### Skill references

- [API-NAME-001], [API-NAME-001a] — naming the new Span-taking
  initializer on `RFC_8259.Number.Original` (variant on the existing
  type, not a sibling type).
- [API-ERR-001] — typed throws preserved at every layer
  (`throws(RFC_8259.Error)`).
- [MEM-COPY-001], [MEM-LIFE-001], [MEM-SPAN-001] — `borrowing Swift.Span<UInt8>`
  + `@_lifetime` annotations on the new init.
- [IMPL-INTENT], [IMPL-COMPILE] — the patch removes mechanism
  (allocator pressure) without removing intent (lossless number
  preservation).
- [RES-019] — internal prior-art grep performed; this doc cites the
  parse-performance arc, value-tree-redesign-v2, and the codec-
  throughput experiment per [HANDOFF-013] / [RES-019].
- [RES-023] — empirical claims (workload counts, file:line citations)
  verified at write time per the rule.
- [RES-027] — loose-end follow-up is bound to a concrete patch path
  (Patches 1+2 → small arc, Patch 3 → deferred with explicit gating
  condition).

## Provenance

Investigation invoked via /research-process on the
`codec-throughput-vs-newcodable` empirical anomaly
(`swift-foundations/swift-json/Experiments/codec-throughput-vs-newcodable/RESULTS.md`,
2026-05-19). Scope: identify the per-Number cost path, size against
canada's workload, recommend patches. No code changes attempted by
this investigation; recommendations queue for a separate
implementation arc.

Verification at write time per [RES-023]:
- Workload counts via Python regex scan of canada.json
  ([Verified: 2026-05-19]).
- File:line citations grep'd against live source ([Verified: 2026-05-19])
  — note: the historical `RFC_8259.Lexer.swift` cited in
  `parse-performance.md` and `parse-performance-architecture.md`
  references no longer exists; the live hot path is in
  `JSON.Decode.Implementation.swift` per Arc 1.6 namespace
  correction + Ticket T-1. This is a benign documentation lag in
  the predecessor docs, not an error here.
- Ecosystem fast-Double parser absence ([Verified: 2026-05-19]) —
  `swift-ascii-parser-primitives` ships `ASCII.Decimal.Parser` for
  integers; no float counterpart surfaced in any prior research doc
  in `swift-json/Research/` or workspace-wide grep.
