# Value Tree Redesign — swift-json v2

<!--
---
version: 1.0.0
last_updated: 2026-05-13
status: RECOMMENDATION
tier: 2
---
-->

## Context

This document is the Tier-2 design follow-on to two predecessor arcs:

| Source | Status | What it established |
|---|---|---|
| `swift-foundations/swift-json/Research/parse-performance.md` v1.2.0 | DECISION | Tiers 0/1/3/4 landed; parse-time parity with Foundation on the canonical workload (1.02× bytes, 1.06× String); residual gap dominated by recursive value-tree teardown. |
| `swift-foundations/swift-json/Research/parse-performance-architecture.md` v1.0.2 | DECISION | Span-specialized internal lexer / parser inside `swift-rfc-8259`; A2 measurement gate passed; **Phase B (arena tree) NOT triggered** under the parse-only framing — but with an explicit re-open clause if a tree-shape-dominated workload surfaces. |

Both predecessors converged on parse-side parity. They left lookup explicitly out of scope.

The current shape of `RFC_8259.Object` (`swift-ietf/swift-rfc-8259/Sources/RFC 8259/RFC_8259.Object.swift:21-37`) is:

```swift
public struct Object: Sendable, Hashable {
    @usableFromInline internal var _storage: [(key: String, value: Value)]
    ...
}
```

And the `subscript(_:)` getter at line 73-76:

```swift
public subscript(_ key: String) -> RFC_8259.Value? {
    get {
        _storage.first { $0.key == key }  // O(n) linear scan
    }
    ...
}
```

The doc comment at line 72 names the problem directly:

> *"Get is O(n). For frequent lookups, consider converting to a Dictionary."*

The canonical lookup-heavy workload is the symbol-graph oracle's tight loop:

```swift
for symbol in symbols {
    _ = symbol.kind.identifier         // 1 keyed lookup on `kind`, 1 on `identifier`
    _ = symbol.identifier.precise      // 1 + 1
    _ = symbol.pathComponents          // 1
    _ = symbol.swiftExtension?.extendedModule  // 1 + 1
}
```

Over 14 552 symbols this is ~73 000 keyed lookups against objects of mean ~6 keys. swift-json's current O(n) linear scan is **materially worse than Foundation**, which uses `NSDictionary` (open-addressed hash). The parse-side parity arc closed the parse gap; this arc must close the lookup gap.

The principal has named three witness-protocol packages as the support layer — `swift-equation-primitives`, `swift-hash-primitives`, `swift-comparison-primitives` — and the candidate storage primitives (`Dictionary.Ordered`, `Dictionary.Slab`, `Hash.Table`, `Memory.Arena`) are all visible in the workspace.

## Question

What value-tree architecture for `swift-json` v2 delivers O(1) lookup that beats `Foundation.JSONSerialization` on lookup-heavy workloads (the symbol-graph oracle's `symbol.kind.identifier` traversal pattern over 14 552 symbols being the canonical case), while:

1. Using the ecosystem's witness-based primitives (`Hash.Protocol`, `Equation.Protocol`, `Comparison.Protocol` from `swift-hash-primitives` / `swift-equation-primitives` / `swift-comparison-primitives`) where they earn their keep over `Swift.Hashable` / `Swift.Equatable` / `Swift.Comparable`?
2. Composing with the already-landed Span lexer/parser inside `swift-rfc-8259` (the predecessor's Phase A1 outcome), preserving the strict-memory-safety contract and typed throws?
3. Keeping the Foundation-free guarantee for production `Sources/` of both `swift-rfc-8259` and `swift-json`?
4. Accepting a clean public-API break — `~Copyable`/`~Escapable` on `RFC_8259.Value` and removal of `Swift.Hashable`/`Swift.Equatable`/`Swift.Sendable` from the public value type are both in scope — with an honest migration story for downstream consumers?

## Analysis

### 1. Prior research — what's already been said

Per [HANDOFF-013] / [RES-019], grepped the relevant corpora for tree-shape, lookup-performance, ordered-dictionary, and `~Copyable` value-tree prior art. Cited; not duplicated:

| Source | What it establishes | Relation to this arc |
|---|---|---|
| `parse-performance.md` v1.2.0 | Tier 4 closed cursor-side wedges; residual is value-tree teardown (~15 % post-A1) | **Direct predecessor.** Lookup wedge is orthogonal; this arc attacks the *read-side* of the same tree the predecessor's parse-side built. |
| `parse-performance-architecture.md` v1.0.2 §7 + §9 | Phase B (arena tree) deferred; "re-opens as a separate research arc per §5's conditional clause" if a tree-dominated workload surfaces | **This arc IS the Phase B re-open** — but framed by lookup, not teardown, as the load-bearing axis. |
| `swift-institute/Research/buffer-arena-conditional-copyable.md` v1.1.0 | Buffer.Arena is unconditionally `~Copyable`; Option A (Storage.Arena ManagedBuffer subclass) recommended but NOT yet implemented as of 2026-05-13 | Constrains any arena-backed tree shape — landing such a shape today requires either accepting `~Copyable Value` OR waiting for the Buffer.Arena restructure. |
| `swift-institute/Research/comparative-dictionary-primitives.md` v1.0.0 | Catalog of `Dictionary` (slab, O(1) remove), `Dictionary.Ordered` (Set.Ordered + Buffer.Linear, O(1) lookup, insertion-order preserved), `.Static`, `.Small`, `.Bounded` variants; gap list (`subscript(default:)`, `removeAll(where:)`, Hash.Protocol bridging) | Primary catalog. `Dictionary.Ordered` is the closest fit for an Object replacement (RFC 8259 §4 requires *neither* preservation nor non-preservation of order; preserving insertion order matches the predecessor's behaviour AND matches Foundation's `[String: Any]` enumeration order in practice). |
| `swift-institute/Research/ecosystem-data-structures-inventory.md` | Cross-package catalog; `Dictionary<K: Hash.Protocol, V>` (slab-backed, O(1) lookup/remove); `Hash.Table` requires `Element: Hash.Protocol`; `Buffer.Linear` and `Set.Ordered` are the building blocks of `Dictionary.Ordered` | Confirms `Dictionary.Ordered` is the right primitive; confirms `Hash.Protocol` is the required key conformance. |
| `swift-primitives/swift-dictionary-primitives/Research/value-storage-buffer-layering.md` | Dictionary.Ordered uses `_keys: Set<Key>.Ordered + _values: Buffer<Value>.Linear` paired 1:1 by index | The shape itself is the answer: ordered keyed access with O(1) lookup, achievable in stdlib-free code. |
| `swift-primitives/swift-hash-primitives/Sources/Hash Primitives Core/Hash.Protocol.swift:1-94` | Under Swift 6.4+, `Hash.Protocol = Swift.Hashable` (SE-0499 collapsed the fork); under <6.4, it's a `~Copyable & ~Escapable`-compatible fork with `borrowing func hash(into:)` | Means `String: Hash.Protocol` already holds on Swift 6.4+; pre-6.4 needs a bridge or stdlib-extension. The institute targets Swift 6.3 + 6.4-dev nightly per the universal CI matrix; the fork is live for the 6.3 row, the typealias is live for 6.4-dev. |
| `swift-primitives/swift-equation-primitives/Sources/Equation Primitives Core/Equation.Protocol.swift:1-91` | Same pattern: `Equation.Protocol = Swift.Equatable` on 6.4+, fork on <6.4 | Same conclusion as Hash. |
| `Sources/JSON/JSON.swift:182-189` | Current `JSON.dictionary: [String: JSON]?` accessor — already builds an ad-hoc `Swift.Dictionary` on every access | An on-demand build per access has cost O(n) PLUS heap allocation; the proposed v2 makes the underlying storage itself O(1). |

The Tier-4 (parse-side) arc carved out lookup explicitly; no prior arc duplicates the design scope below.

### 2. The wedges THIS arc must attack

The post-Tier-4 wall-clock on the canonical workload sits at parse parity. But **lookup-throughput is not measured** in the existing harness. What the symbol-graph oracle's traversal pattern measures:

| Operation | Per-symbol count | Total over 14 552 symbols | Current cost (per call) |
|---|---|---|---|
| `Object[key]` keyed lookup | ~6 | ~87 000 | O(n) linear scan; n = key count of that object (mean ~6) |
| `Array[i]` indexed access | ~1 | ~14 552 | O(1) — already fine |
| `Value` enum case extract | many | many | O(1) — already fine |

The compound cost of the linear-scan keyed lookup is approximately **87 000 × 6 = ~520 000 byte-string comparisons** for the oracle's traversal of one symbol-graph file. Foundation's `NSDictionary` does **~87 000 hash + ~87 000 probe** — roughly 87 000 String-hash ops + 87 000 equality ops, with the equality typically firing once per lookup (modulo collisions).

The wedges this arc closes:

1. **O(n) keyed lookup** on `RFC_8259.Object` — replace with O(1) hash-table-backed lookup.
2. **Re-walk-the-tree-for-Dictionary access cost** — `JSON.dictionary` (`Sources/JSON/JSON.swift:182-189`) currently builds a fresh `Swift.Dictionary` on every access. The v2 shape obviates this entirely.
3. **No-cache key-hash recomputation across repeated lookups** — secondary; addressed naturally by Dictionary.Ordered's hash-table.

The wedges this arc explicitly does **NOT** attack:

- Recursive value-tree teardown (the ~15 % residual from Tier 4). Closing it requires either arena-allocated nodes (which forces `~Copyable Value` and forces the Buffer.Arena restructure that's still RECOMMENDATION) or a different tree shape. Section 4.4 below evaluates whether this arc should attack it; the answer turns out to be conditional.
- Parse-side performance below the A1 parity baseline. The v2 shape must not regress parse materially.

### 3. Candidate architectures

Per [RES-010b]: four candidates plus what their survey surfaces.

#### L1 — Drop-in ordered dict, Copyable Value (smallest break)

**Shape.** Replace `RFC_8259.Object._storage: [(String, Value)]` with `_storage: Dictionary<String, Value>.Ordered`. Keep `RFC_8259.Value` as today: enum, `Sendable`, `Hashable`. Keep public API surface; the subscript becomes O(1).

```
public struct Object: Sendable, Hashable {
    @usableFromInline
    internal var _storage: Dictionary_Primitives_Core.Dictionary<String, Value>.Ordered

    public subscript(_ key: String) -> RFC_8259.Value? { _storage[key] }  // O(1) now
    public var count: Int { Int(bitPattern: _storage.count) }
    public func makeIterator() -> Iterator { ... }                          // walks _keys + _values in insertion order
}
```

`Dictionary.Ordered` is `Copyable when Value: Copyable` (per `swift-primitives/swift-dictionary-primitives/Sources/Dictionary Primitives Core/Dictionary.Ordered.swift:111-117`); Value here is `RFC_8259.Value` which stays Copyable; so `Object` stays Copyable. `Sendable` survives. `Hashable` survives (Dictionary.Ordered is `Hashable where Key: Hashable, Value: Hashable`).

**Witness-protocol composition.** The keys are `String`, which is `Swift.Hashable`. Under Swift 6.4+ `Hash.Protocol = Swift.Hashable` (typealias), so `String: Hash.Protocol` holds for free. Under Swift 6.3 (the institute's other supported row), the institute's `Hash.Protocol` is a fork; the `Hash Primitives Standard Library Integration` module (`swift-hash-primitives/Sources/Hash Primitives Standard Library Integration/`) is the conformance bridge — `String: Hash.Protocol` MUST be declared there or imported transitively for L1 to compile under the 6.3 row.

[VERIFICATION NEEDED 2026-05-13: confirm `String: Hash.Protocol` conformance is published from `Hash Primitives Standard Library Integration` under the Swift 6.3 row. If absent, this is a pre-A0 fix — one-line conformance bridge in `swift-hash-primitives`. If present, this row no longer fires.]

**Wedges attacked.**

| Wedge | Closed? |
|---|---|
| O(n) keyed lookup | **Yes.** Dictionary.Ordered subscript is O(1) average. |
| `JSON.dictionary` rebuild-on-access | **Yes-but-cosmetic.** Can deprecate the accessor or rewrite it to return a typed view; downstream consumers stop paying. |
| Tree teardown | **No.** Same enum + boxed values; same recursive deinit. |

**Lookup-throughput projection.** Foundation's `NSDictionary` keyed-lookup is ~30–50 ns on Apple Silicon (Apple's CFDictionary is highly tuned, but for the small-object case the bridge overhead from `[String: Any]` evens it out). `Dictionary.Ordered` lookup is composed of:

1. `String.hashValue` — same cost as Foundation's String-hash.
2. `Hash.Table.position(forHash:equals:)` — linear-probe slot scan; same memory access pattern as `NSDictionary`'s open-addressed probe.
3. `Set<Key>.Ordered`'s position lookup — index in `Buffer<Element>.Linear`.
4. Index retag + Buffer.Linear subscript on `_values` — O(1).

Confidence projection: **Dictionary.Ordered lookup matches or modestly beats Foundation** because the institute's path stays in typed Swift (no `Any`-bridge) and the hash table is open-addressed power-of-two-sized (`bucketCapacity` per `Hash.Table.swift:115-125`). Magnitude estimate: **0.8–1.2× Foundation per-lookup**, with the lookup-heavy workload's total ratio **likely net-faster than Foundation** because the bridge overhead is gone.

**Parse-time delta.** Building `Dictionary.Ordered` instead of `Array.append` per member has a SMALL cost: each insertion is now `hashValue + Hash.Table.insert + Buffer.Linear.append` instead of `Array._storage.append`. For pretty-printed JSON with ~6 keys per object this is ~6 hash ops per object. Order: ~10–25 % slower parse on object-heavy inputs. The A1 measurement gives 0.304 s on the bytes path; a 20 % regression is 0.365 s, **still well below 1.3× Foundation** (which would be 0.39 s).

**API break magnitude.** Cosmetic:

| Public API | Today | v2 (L1) |
|---|---|---|
| `Object[key]` | O(n) `Value?` | **O(1)** `Value?` |
| `Object.count` | `Int` | `Int` (cast from `Dictionary.Ordered.count`) |
| `Object.isEmpty` | `Bool` | `Bool` |
| `Object.keys` | `[String]` | `[String]` (built from `_storage.map { $0.key }`) |
| `Object.values` | `[Value]` | `[Value]` |
| `for (k, v) in obj` | `Swift.Sequence` | `Swift.Sequence` (Dictionary.Ordered conforms) |
| Hashable/Equatable/Sendable | Yes | Yes |
| ExpressibleByDictionaryLiteral | Yes | Yes (small adapter) |
| `JSON.dictionary: [String: JSON]?` | Builds on access | Either keep as bridge or deprecate-then-remove |

The break is **literally zero for first-order consumers**: `Object[key]?.string` is still `Object[key]?.string`. The only break is for code that reaches into `_storage` directly, which is `@usableFromInline internal` and therefore not a public-API surface.

**Lifetime ergonomics.** Unchanged. `Value` stays Copyable; `let cached = json.user.name` works; `for (k, v) in obj.object! { ... }` works.

**Streaming compatibility.** `JSON.ND.stream` (`Sources/JSON/JSON.Stream.swift:75-147`) and `JSON.parse(collecting:)` unaffected — they produce `JSON` (= `RFC_8259.Value`) the same way; the only difference is what `Object` stores internally.

**`JSON.Serializable` story.** Unchanged. Protocol takes `JSON` (Copyable Value tree), produces it; no signatures change.

**Composition with the Span lexer.** Unaffected. The parser builds `RFC_8259.Object` via its public initializer; replacing the storage representation is invisible to the lexer. The initializer becomes `init(_ elements: [(key: String, value: Value)]) { for (k, v) in elements { _storage.set(k, v) } }` — slightly more work per element but Big-O-equivalent.

**Memory-safety contract.** Unchanged. Dictionary.Ordered is `@safe` per its declaration (`Dictionary.Ordered.swift:83`); no new SPI imports; the `@_spi(Unsafe)` import in the lexer is unaffected.

**Implementation cost.** Tiny — ~150–250 LoC across:

- `RFC_8259.Object.swift` — replace `_storage` declaration, rewrite subscript / count / isEmpty / keys / values / makeIterator / Equatable / Hashable.
- `RFC_8259.Object.Iterator.swift` — wrap `Dictionary.Ordered.Iterator` rather than `IndexingIterator`.
- `RFC_8259.Parser.Span.swift` — adapt object-building (parser already accumulates `(key, value)` pairs into a `[(String, Value)]`; either continue and pass to `Object.init(_:)`, OR insert into `Dictionary.Ordered` directly via `set(_:_:)`).
- `swift-rfc-8259/Package.swift` — add dep on `swift-dictionary-primitives` (Layer 1 → Layer 2 is allowed; `swift-rfc-8259` is L2 standard, depending on L1 primitive).

Plus a Swift 6.3 row fix if `String: Hash.Protocol` is not yet bridged.

**Risk.**

- (a) **Parse regression more than projected.** Mitigation: bench harness already exists; measure in A1 phase.
- (b) **Hash.Protocol bridging gap on Swift 6.3.** Mitigation: one-line conformance in `swift-hash-primitives`'s integration module. The institute targets both 6.3 and 6.4-dev in the universal CI matrix; this row must pass.
- (c) **The "Get is O(n)" doc comment is load-bearing in some external code.** No callable contract is broken.

#### L2 — Full v2 break, `~Copyable` Value tree, arena-bound

**Shape.** Make `RFC_8259.Value` `~Copyable & ~Escapable`; allocate Object members and Array elements into a `Memory.Arena` owned by the parse result; conform `Value` to the witness-protocol triple `Hash.Protocol / Equation.Protocol / Comparison.Protocol` (the SE-0499 borrowing variants); drop `Swift.Hashable / Swift.Equatable / Swift.Sendable` from the public Value.

**Wedges attacked.** All — including tree teardown (single arena drop), tree allocation churn (single arena allocation), AND O(1) lookup (arena-backed hash table per Object).

**Witness-protocol composition.** This is where the named primitives earn their keep. `RFC_8259.Value` is `~Copyable`; the SE-0499 borrowing variants of Hash/Equation/Comparison are exactly the right contract. `String: Hash.Protocol` (the keys) holds via the same Standard Library Integration bridge.

**Constraint from prior research.** `swift-institute/Research/buffer-arena-conditional-copyable.md` v1.1.0:

> *"Cannot conform to Copyable: Arena has deinit (manages _meta allocation lifecycle). … extension Buffer.Arena: Copyable where Element: Copyable {} ← NOW POSSIBLE [after Option A]"*

But Option A (Storage.Arena ManagedBuffer subclass) is **RECOMMENDATION, not DECISION** as of 2026-05-13. To land L2 without waiting for that arc requires either:

1. Accept that `RFC_8259.Value` is unconditionally `~Copyable` (forfeit Sendable / Hashable / Equatable / `let cached = json.user.name`); OR
2. Wait for the Buffer.Arena restructure (an unknown number of weeks/months); OR
3. Roll our own arena variant inside `swift-rfc-8259` (forbidden per [DS-020] without a second consumer — and would be one).

**Lookup-throughput projection.** Best of all four. Arena-allocated lookup means keys, values, and hash-table buckets all live in the same contiguous allocation: cache-hit-warm probes, minimal pointer chasing. Magnitude estimate: **~0.6–0.8× Foundation per-lookup**, **strongly beats** the lookup-heavy total.

**Parse-time delta.** Likely net improvement of ~10–20 % beyond A1: arena bump-allocation replaces per-Value heap allocation; tree-teardown is O(1) (single deallocate). The post-A1 profile attributed 15 % to teardown — this directly closes that wedge.

**API break magnitude.** Severe:

| Public API | Today | v2 (L2) |
|---|---|---|
| `RFC_8259.Value` Copyability | Yes | **No — `~Copyable`** |
| `RFC_8259.Value: Sendable, Hashable` | Yes | **No** — replace with `Hash.Protocol` (borrowing API) |
| `let cached = json.user.name` | Works | **Doesn't work** — needs `withUnsafe`-style borrowing API |
| Hold across `await` | Works (Sendable) | **Doesn't work** without explicit transfer protocols |
| `for (k, v) in obj` | Works | **Custom forEach** required |
| `json.dictionary: [String: JSON]?` | Works | **Removed** or returns owned snapshot only |
| `JSON.Serializable.deserialize(_ json: JSON)` | Takes `JSON` by value | Must take `borrowing JSON` (or consuming JSON for one-shot consumers) |
| `JSON.parse.prepared() / .located()` | Sendable | Must be re-thought — output is now ~Copyable |
| `JSON.ND.stream` | Produces `Result<JSON, Error>` | `Result` doesn't compose with ~Copyable Success; needs a new shape (e.g., async iteration with consuming yield) |
| `Array.literal: [JSON]` round-trips | Works | Doesn't survive arena lifetime |

**Lifetime ergonomics.** Hostile. Every `let cached = json.user.name` becomes:

```swift
try json.user.withName { name in
    // do something with borrowed name
}
```

This is a serious downgrade for the 95 % of consumers who treat JSON as a value tree.

**Streaming compatibility.** Broken. `JSON.ND.stream` produces an `AsyncSequence<Result<JSON, JSON.Error>>`. If `JSON` is `~Copyable`, `Result<JSON, JSON.Error>` doesn't compose (Result is Copyable in stdlib); AsyncSequence yields are Sendable-required for cross-task delivery. The downstream API would need a full streaming-redesign that delivers borrowed-or-consumed values — significant scope creep.

**`JSON.Serializable` story.** Compatible but restrictive: `deserialize(_ json: borrowing JSON)` works; `serialize(_ value: Self) -> JSON` requires consuming arena allocation (typically by passing the arena in, or by returning into a caller-provided arena).

**Composition with the Span lexer.** Compatible — the lexer is already `~Copyable & ~Escapable`; building into an arena from a `~Copyable & ~Escapable` cursor is a natural lifetime composition.

**Memory-safety contract.** Preserved if the arena is `@safe` (it is). No new SPI imports beyond what arena consumers already do.

**Implementation cost.** Very high — ~3000–5000 LoC including:

- New `RFC_8259.Value` `~Copyable` enum with arena-bound payload references.
- New `RFC_8259.Object` / `.Array` as arena-bound views.
- New `RFC_8259.Parser.Span` arena-emitting variant.
- New `JSON` public surface (borrowing accessors, withSubscript closures, custom forEach).
- New `JSON.ND.stream` shape (delivers values via consuming yield or borrows under a callback).
- New `JSON.Serializable` deserialize signature.
- Public-API migration matrix for every dynamic-member-lookup chain in downstream code.

**Risk.** Very high. The ergonomics of `json.user.name.string` is what makes swift-json desirable over Foundation's `[String: Any]` casting; losing that on the v2 break is a downgrade most consumers will refuse.

#### L3 — Hybrid (small linear, large hashed)

**Shape.** `RFC_8259.Object._storage` is an enum:

```swift
enum Storage {
    case small([(String, Value)])            // ≤ N entries, linear scan is faster than hashing
    case large(Dictionary<String, Value>.Ordered)
}
```

Auto-promote at parse-time when count exceeds N (typically 8–16).

**Wedges attacked.** Lookup wedge on objects > N keys; teardown wedge unchanged.

**Witness-protocol composition.** Same as L1 — keys are `String`, conforming via the integration bridge.

**Lookup-throughput projection.** Mixed. On objects ≤ N: equivalent to today's linear scan. On objects > N: O(1) hashed. The symbol-graph workload has mean ~6 keys per object — **most of the workload is in the "small" path**. The hybrid in fact buys NOTHING on the canonical workload until objects grow large.

Actual lookup measurements on objects of size 6 suggest the linear-scan path is competitive with hashed lookup when the linear scan can be vectorized (cache-warm contiguous memory, no hash computation overhead). Foundation may be using exactly this hybrid (CFDictionary historically has a small-dict optimization).

**Parse-time delta.** Marginal — parse cost equivalent to L1 above the threshold; cheaper than L1 below it.

**API break magnitude.** Same as L1 — internal shape change, no public-surface break.

**Lifetime / streaming / Serializable / Span / safety.** Same as L1.

**Implementation cost.** ~400–600 LoC; the auto-promotion logic + iterator across the enum variants adds complexity over L1.

**Risk.** The chosen N is a magic number; the workload-dependent crossover point is empirical. Bench-tuning required.

#### L4 — Lazy index, Copyable Value (zero-cost-when-not-looking)

**Shape.** `RFC_8259.Object._storage: [(String, Value)]` stays as today. Add a lazy `_index: Hash.Table<String>?` — `nil` until the first keyed lookup, then built O(n) and cached. Subsequent lookups O(1).

```swift
public struct Object: Sendable, Hashable {
    @usableFromInline internal var _storage: [(key: String, value: Value)]
    @usableFromInline internal var _index: Hash.Table<String>? = nil

    public subscript(_ key: String) -> RFC_8259.Value? {
        get {
            // Build index on first lookup
            if _index == nil { mutating { self._index = ... } }
            // ... O(1) lookup
        }
    }
}
```

**Wedges attacked.** Lookup wedge on objects accessed at least twice; first-access pays O(n).

**Witness-protocol composition.** Same — `Hash.Table<String>` requires `String: Hash.Protocol`; integration bridge applies.

**Lookup-throughput projection.** Excellent for repeated lookups; worse than L1 for one-shot lookups (which pay O(n) anyway with L1's pre-built index, but L4 pays O(n) twice: once to build, once amortised). The symbol-graph oracle's loop pattern hits each object's `kind`, `identifier`, `pathComponents` etc. — multiple lookups per object → the build pays.

**Parse-time delta.** Zero. Parse doesn't build the index; it's only built on first lookup.

**API break magnitude.** Smallest of all four. The index is internal; the public surface is byte-identical to today.

**Lifetime / streaming / Serializable / Span / safety.** All preserved.

**Implementation cost.** ~150–200 LoC — index struct, lazy initialization (which requires `mutating` get; subscript getters that mutate are tricky; the actual implementation needs a mutable cache).

**Risk.**

- (a) **Subscript getter that mutates self.** In Swift this requires `mutating get`, which means `Object` doesn't have a non-mutating subscript and forces all uses to mutate. *This is a public-API break*. Workaround: use a class-backed `_index` (cache in a class, share copy-on-write) — re-introduces ARC traffic that L1's pure-value-type approach avoids.
- (b) **The Hashable conformance** must include or exclude the index — exclude for value equality semantics; the cached-index serialization issue (Sendable conformance with internal mutable state).
- (c) **Two competing storage representations** of the same object (the linear array + the index), like L3, but with worse mental model — "is the object indexed yet?" is a runtime question.

#### Option comparison summary

| Criterion | L1: Ordered dict | L2: ~Copyable arena | L3: Hybrid | L4: Lazy index |
|---|---|---|---|---|
| O(1) lookup | **Yes** | Yes | Above threshold | Yes (post-build) |
| Beats Foundation on lookup-heavy workload | Likely yes | Strongest | Marginal | Yes |
| Parse regression vs A1 | ~10–25 % | Improvement | Minimal | None |
| Tree-teardown wedge closed | No | Yes | No | No |
| Public-API break | Tiny | Severe | Tiny | Tiny |
| Lifetime ergonomics | Unchanged | Hostile | Unchanged | Unchanged |
| Streaming compatibility | Preserved | Broken (full redesign) | Preserved | Preserved |
| `JSON.Serializable` survives | Yes | Compatible-but-restrictive | Yes | Yes |
| Composes with Span lexer | Yes | Yes | Yes | Yes |
| Memory-safety preserved | Yes | Yes | Yes | Yes |
| Foundation-free preserved | Yes | Yes | Yes | Yes |
| Witness-protocol leverage | `String: Hash.Protocol` (modest) | Full triple, load-bearing | Same as L1 | Same as L1 |
| Implementation cost | ~150–250 LoC | ~3000–5000 LoC | ~400–600 LoC | ~150–200 LoC |
| Independent shippable phases | Yes (small) | No (big-bang) | Yes | Yes |
| Reversibility | High | Low | High | High |
| Dependencies on unlanded research | None | Buffer.Arena Option A (RECOMMENDATION) | None | None |

### 4. Decision axes

Two axes dominate:

#### 4.1 Witness-protocols: what's the load-bearing benefit?

The principal explicitly named `swift-equation-primitives`, `swift-hash-primitives`, `swift-comparison-primitives` as the support layer to lean on. Where do they actually earn their keep?

| Architecture | Hash.Protocol on String (keys) | Hash.Protocol on Value | Equation.Protocol on Value | Comparison.Protocol on Value |
|---|---|---|---|---|
| L1 | Required, via Standard Library Integration | N/A — Value stays Swift.Hashable | N/A — Value stays Swift.Equatable | Not used |
| L2 | Required | **Load-bearing — only way to hash ~Copyable Value** | **Load-bearing — only way to equate ~Copyable Value** | Useful for ordered traversal |
| L3 | Required, via Standard Library Integration | N/A | N/A | Not used |
| L4 | Required, via Standard Library Integration | N/A | N/A | Not used |

**Witness protocols earn their keep ONLY on L2.** In L1/L3/L4, the keys (Strings) are well-served by `Swift.Hashable` directly — and under Swift 6.4+, `Hash.Protocol = Swift.Hashable` is a typealias, so the witness packages add zero indirection. The Standard Library Integration bridge is the only meaningful import.

The principal's framing ("use these where they earn their keep") points at L2 — but L2's other costs (severe API break, hostile lifetime ergonomics, broken streaming, dependency on RECOMMENDATION-status upstream research) are the binding constraint.

**Practical conclusion**: under Swift 6.4+, the witness protocols are conformance-equivalent to stdlib (zero-cost typealias). The institute's CI matrix targets both 6.3 and 6.4-dev — the institute investment in the witness primitives is correct, but on this specific design decision they primarily provide the future-proofing bridge for any later move to ~Copyable. L1 takes one explicit dep on the integration module; that's the entire "witness primitives earn their keep" footprint on this arc.

#### 4.2 Lookup-throughput vs lifetime ergonomics

The win condition is "beat Foundation on lookup-heavy workloads." All four architectures achieve O(1) lookup; only L2 is *materially* better than L1 on raw per-call latency (arena-local cache locality). But L2's per-call advantage is dwarfed by the ergonomics damage — the symbol-graph oracle is a closed-loop tool that can be written to use borrowing APIs, but the typical swift-json consumer has dynamic-member-lookup chains like `json.user.profile.avatar.url.string` that the L2 break destroys.

The honest framing: **L1 is materially-but-not-radically faster than Foundation. L2 is more decisively faster. The decisiveness gap doesn't justify the ergonomics gap on the workloads that matter to swift-json's positioning.**

### 5. The recommended architecture

**RECOMMENDED: L1 — Ordered-dict, Copyable Value.**

Replace `RFC_8259.Object._storage: [(String, Value)]` with `Dictionary_Primitives_Core.Dictionary<String, RFC_8259.Value>.Ordered`. Keep `RFC_8259.Value` enum as-is (Copyable, Sendable, Hashable). Keep `RFC_8259.Array._storage: [Value]` as-is (no benefit to changing; `Array<Value>` already has O(1) indexed access). All four named witness primitives are imported transitively via `swift-dictionary-primitives` → `swift-hash-primitives` → `String: Hash.Protocol` integration bridge; no direct conformance burden in `swift-rfc-8259`.

#### 5.1 Why L1 over L2

1. **O(1) lookup is the win condition; L1 delivers it.** L2 delivers slightly faster O(1) lookup but at severe ergonomic cost.
2. **L2 depends on unlanded upstream research.** `Buffer.Arena: Copyable when Element: Copyable` requires Option A from `buffer-arena-conditional-copyable.md` v1.1.0 to land. As of 2026-05-13 that's RECOMMENDATION, not DECISION; landing it is a separate multi-package arc. L1 can ship today.
3. **`Swift.Sendable` survival matters.** `JSON.parse.prepared()` is documented as the API for "parse multiple documents concurrently" (`Sources/JSON/JSON.Parse.swift:153-211`). Under L2 that contract breaks (the parsed `JSON` is `~Copyable`, can't cross actors as a value). L1 preserves it.
4. **The dynamic-member-lookup chain is swift-json's value proposition.** `json.user.name.string` is what the README sells. L2 fundamentally compromises this; L1 doesn't.
5. **The witness primitives' load-bearing benefit doesn't fire on L1's String keys.** They earn their keep only when Value itself becomes ~Copyable — and that's the L2 cost.
6. **Reversibility.** L1 is reversible — if a future arc demonstrates that the lookup-only optimization is insufficient and the teardown wedge dominates a real workload, the L2 arc can be opened then with full evidence. L2 is one-way.

#### 5.2 Why L1 over L3

L3's hybrid pays nothing on the canonical workload (mean object size ~6, all in the small-bucket path). The crossover-point empirical work and dual-iteration complexity buys negligible benefit for compounding implementation cost. Defer; if measurement shows L1 is materially worse than Foundation on small-object lookups, fold in L3's auto-promotion as a follow-on.

#### 5.3 Why L1 over L4

L4 is plausible but introduces two avoidable defects:

- A mutating subscript getter (the cleanest implementation), which forces all `Object` consumers to use `var` bindings — a public-API break that's actually larger than L1's break in practice.
- A *second* representation alongside the linear array — both must be kept in sync on mutation, and the equality semantics need careful spec to avoid "two objects with same contents, one indexed, one not, hash differently."

L1's single representation is structurally simpler.

#### 5.4 What L1 does NOT close

The tree-teardown wedge (~15 % post-A1) remains. The honest framing: the lookup-heavy workloads are not the same as the teardown-heavy workloads. The symbol-graph oracle parses-once-walks-many — lookup dominates total time once L1 lands. A future hypothetical workload that parses-then-discards-rapidly (e.g., per-request micro-parses in a hot server loop at < 100 µs scale) would shift the dominant wedge to teardown; that workload would re-open the L2/arena arc with empirical evidence. The conditional clause in `parse-performance-architecture.md` §5 stays available for that case.

#### 5.5 Witness primitives: explicit role in L1

| Primitive | Role on L1 | Mechanism |
|---|---|---|
| `swift-hash-primitives` (`Hash.Protocol`) | Required — `Hash.Table<String>` inside `Dictionary.Ordered` requires `String: Hash.Protocol` | Imported transitively via `swift-dictionary-primitives` |
| `swift-equation-primitives` (`Equation.Protocol`) | Refined by `Hash.Protocol` | Same transitive route |
| `swift-comparison-primitives` (`Comparison.Protocol`) | Not used on L1 (no ordered traversal at the lookup-table layer) | N/A |
| `Hash Primitives Standard Library Integration` | **Load-bearing** — provides `String: Hash.Protocol` conformance bridge | Must be imported (or re-exported transitively) in `swift-rfc-8259` |
| `swift-dictionary-primitives` (`Dictionary.Ordered`) | Provides O(1) keyed ordered storage with insertion-order preservation | Direct dep added to `swift-rfc-8259/Package.swift` |
| `swift-memory-primitives` (`Memory.Arena`) | **Not used on L1.** Reserved for the conditional L2 follow-on if/when the teardown-heavy workload surfaces. | Stays a dep candidate for the future arc |

The principal's framing of "leverage the ecosystem's witness-based primitives" is fulfilled on L1 by **consuming Dictionary.Ordered**, which internalises all four. L1 doesn't directly conform any new type to `Hash.Protocol`; it leans on the conformance chain that the dictionary catalog already requires. That's the natural fit — the witness machinery is what makes the institute's `Dictionary` work on `~Copyable` Values upstream of swift-json; swift-json benefits transitively from that investment without paying the cost of conforming `RFC_8259.Value` itself.

### 6. Phased landing plan

Each phase independently shippable and reversible. Mirrors the predecessor doc's A0/A1/A2 shape with measurement gates.

#### Phase L1-0 — Pre-A0 verification + lookup-bench mode (½ day)

Before any storage change, two things must be verified and one must be built:

1. **Verify `String: Hash.Protocol` is reachable from `swift-rfc-8259`.** Grep the Hash Primitives integration module (`swift-primitives/swift-hash-primitives/Sources/Hash Primitives Standard Library Integration/`) for `extension String: Hash.Protocol`. If missing under Swift 6.3 (which uses the fork), the L1 plan halts here and the pre-A0 fix is a one-line conformance added upstream — a tiny PR to `swift-hash-primitives`. Under Swift 6.4+ the typealias means `String: Swift.Hashable` is the same as `String: Hash.Protocol`; this row holds automatically.

2. **Verify Dictionary.Ordered's runtime cost on a 6-key/object workload matches the projection.** Build a 100-line microbenchmark target inside `Experiments/parse-performance-bench` (a new mode) that creates 14 552 `Dictionary<String, Int>.Ordered` of ~6 keys each and does the symbol-graph access pattern. Compare to `Swift.Dictionary<String, Int>` (Foundation-bridge equivalent for the access pattern, since the workload is closed-loop in Swift). If Dictionary.Ordered's per-lookup time is materially slower than Swift.Dictionary, the L1 architecture is at risk and the arc halts for re-evaluation.

3. **Add a `lookup` mode to `Experiments/parse-performance-bench`.** New CLI mode that:
   - Parses the file once (per parser).
   - Runs the symbol-graph oracle's traversal pattern N iterations.
   - Reports wall-clock per-lookup AND lookup-throughput-mb/s-equivalent.
   - Engages all four parsers: Foundation, current swift-json, the L1 swift-json (post-implementation), and (optionally) the L1-microbench dictionary-only path from step 2.

The mode is added BEFORE the storage change; the current swift-json (pre-change) numbers establish the baseline that L1-1 below must beat.

**Disposition.** Documented inline in the bench harness; pre-A0 commit not part of the storage-change PR.

#### Phase L1-1 — Replace Object storage + dispatch fork (1 arc, ~3–5 days)

1. **`swift-rfc-8259/Package.swift`:**
   - Add `.package(path: "../../swift-primitives/swift-dictionary-primitives")` (or url-form per [PKG-DEP-*] release-time rules).
   - Add `.product(name: "Dictionary Ordered Primitives", package: "swift-dictionary-primitives")` to the RFC 8259 target (narrow import per [MOD-015]; Dictionary.Ordered is the only variant we use).
   - Add `.product(name: "Hash Primitives Standard Library Integration", …)` if it isn't transitively re-exported.

2. **`swift-rfc-8259/Sources/RFC 8259/RFC_8259.Object.swift`:** replace declaration:

   ```swift
   extension RFC_8259 {
       public struct Object: Sendable, Hashable {
           @usableFromInline
           internal var _storage: Dictionary_Primitives_Core.Dictionary<String, Value>.Ordered

           public init() { _storage = .init() }

           public init(_ elements: [(key: String, value: Value)]) {
               _storage = .init()
               for (k, v) in elements { _storage.set(k, v) }
           }
       }
   }
   ```

   Rewrite `count`, `isEmpty`, `keys`, `values`, `subscript(_:)`, `makeIterator`, `Hashable`, `Equatable`, `CustomStringConvertible`. The `Iterator` either wraps `Dictionary.Ordered.Iterator` or stays index-based on `_storage` exposed positions.

3. **`swift-rfc-8259/Sources/RFC 8259/RFC_8259.Object.Iterator.swift`:** rewrite to bridge `Dictionary.Ordered`'s iterator to the `(key: String, value: Value)` tuple shape callers expect.

4. **`swift-rfc-8259/Sources/RFC 8259/RFC_8259.Parser.Span.swift`:** in `parseObject`, the existing accumulator is `var members: [(String, Value)] = []` followed by `RFC_8259.Object(members)`. The cheapest path is to keep the accumulator AND pass into the public init, which under the new shape does `Dictionary.Ordered.set` per member. Alternative: stream directly into a `Dictionary.Ordered` via an `init` that takes an `inout` builder. Decide in implementation; bench both if unclear.

5. **`Sources/JSON/JSON.swift`:** the `dictionary: [String: JSON]?` accessor (line 182-189) becomes either:
   - A pass-through that maps the typed Dictionary.Ordered (still O(n) on access but the underlying storage is O(1) for the `[key]` path callers should be using); OR
   - **Deprecated** in favour of `.object` (which now returns a typed view efficiently); OR
   - **Removed** as the v2 cleanup. Decide based on downstream-impact survey (`grep -r ".dictionary" swift-foundations/ swift-ietf/ swift-primitives/ swift-standards/ 2>/dev/null`).

6. **Tests:** all 124 existing `RFC_8259` tests must continue to pass. New tests cover insertion-order preservation under set/get/replace cycles, equality with stdlib `[String: Value]` literal, the `subscript` setter behaviour with insert-vs-update semantics.

7. **Bench:** rerun the `lookup` mode added in L1-0. Record before/after.

**Success criteria.**

- All tests green.
- `lookup` bench: swift-json's per-lookup time ≤ Foundation's per-lookup time on the symbol-graph workload, with ≥ 20 % overall throughput improvement on the lookup-heavy traversal (i.e., the symbol-graph oracle's full reduce should drop materially).
- `all` bench (parse-throughput): swift-json's parse path within 1.3× Foundation on both String and `[UInt8]` paths (i.e., ≤ 0.39 s on the canonical 86 MB workload). The 1.02× / 1.06× A1 numbers MAY regress to ~1.20×–1.25× — this is acceptable.

#### Phase L1-2 — Measurement gate

Bench results determine disposition:

- **Outcome 1**: lookup-bench beats Foundation, parse stays under 1.3×. L1 lands. Document as v2.0.0 release. The L2/arena follow-on stays parked per `parse-performance-architecture.md` §5's conditional clause.
- **Outcome 2**: lookup-bench matches Foundation but parse regresses past 1.3×. Investigate per-object insertion cost; consider L3-style hybrid (small-bucket linear) as an opt-in. Re-open ARC.
- **Outcome 3**: lookup-bench is materially worse than Foundation despite O(1) storage. Investigate where Dictionary.Ordered's overhead comes from (Hash.Table.position vs `NSDictionary`'s tuned probe). May lead to a Hash.Table-level perf arc, not a swift-json arc. Re-open at the primitives layer.

Per `[RES-027]` the bench-mode addition in L1-0 is what makes the gate empirical rather than speculative — without the lookup mode, L1-2 is a guess.

#### Phase L1-3 — Public API cleanup (conditional, ½ day)

If L1-1 ships cleanly, optional final touch-up:

- Decide whether to deprecate `JSON.dictionary: [String: JSON]?` (cosmetic — the underlying storage is now O(1)).
- Decide whether to add a new typed accessor that exposes the `Dictionary.Ordered` directly for consumers that want it (potentially `json.objectTyped: RFC_8259.Object?` or similar — naming TBD per [API-NAME-001]).
- Document the v2.0.0 changelog.

#### Phase L2 — DEFERRED (conditional)

Re-open ONLY if both:

1. A second hot consumer beyond the symbol-graph oracle surfaces with a workload where the tree-teardown wedge (rather than lookup) is the dominant cost.
2. `buffer-arena-conditional-copyable.md` Option A has landed (i.e., `Buffer.Arena: Copyable when Element: Copyable` works).

Until both fire, L2 stays the conditional Phase B of the predecessor arc. This document is the **L1 design**; the L2 plan stays in `parse-performance-architecture.md` v1.0.2 §5.

### 7. Risks and honest-disagreement notes

| Risk | Likelihood | Mitigation |
|---|---|---|
| Dictionary.Ordered per-lookup is materially slower than Foundation despite O(1) | Low | Pre-A0 microbench in L1-0 catches this before the storage change lands. If true, the lookup arc shifts to the primitives layer (Hash.Table optimization), not swift-json. |
| Parse regresses past 1.3× Foundation | Medium | Measure during L1-1; if true, consider whether the bench-time `set(_:_:)` is the cost or whether bulk init via Builder API would help. |
| `Object: Hashable` semantics change vs today | Low-medium | The current `Hashable` implementation (`Object.swift:138-146`) hashes the `_storage` count and each `(key, value)` in order. `Dictionary.Ordered: Hashable where Key: Hashable, Value: Hashable` does the same. Verify in tests. |
| `String: Hash.Protocol` bridging gap under Swift 6.3 | Medium | Pre-A0 verification step; one-line conformance in `swift-hash-primitives` if missing. |
| Insertion-order semantics under update (today: in-place update preserves position; Dictionary.Ordered: same per its doc) | Low | Verified in `Dictionary.Ordered.swift:75-79` doc comment. Add tests anyway. |
| Downstream consumers of `Object._storage` (none expected — it's `@usableFromInline internal`) | Very low | Grep `swift-foundations/ swift-ietf/` to confirm zero external references. |
| `JSON.ND.stream` (`Sources/JSON/JSON.Stream.swift:83-147`) state-machine workaround on `@unchecked Sendable` survives the change | High likelihood of working | The state machine wraps `AsyncIteratorProtocol`; nothing about it depends on `RFC_8259.Object`'s storage shape. |
| The hash-table probe cost on small objects (size ~6) is competitive with linear scan | Medium-likely | If empirically equivalent in the L1-0 microbench, the lookup gain may be smaller than projected on the canonical workload — though still O(1) vs O(n) for large objects. The win is asymptotic; the constant may not dominate. |
| `Buffer.Arena: Copyable` lands in a future arc and makes L2 cheap — should we wait? | Low question, important answer | NO. L1 delivers the user-visible win in days, not weeks-or-months. If L2 becomes cheap later, the L1→L2 migration is a separate, well-scoped arc with empirical L1 numbers to compare against. Waiting violates the predecessor's `[ARCH-LAYER-008]` correctness-driver discipline (pre-1.0 = ship the right architecture for the current evidence). |
| Witness primitives (Hash/Equation/Comparison) are *less* load-bearing on L1 than the principal's framing suggested | Honest disagreement | The framing of "lean on the witness primitives" is fulfilled on L1 by *consuming Dictionary.Ordered*, which is the package that internalises them. swift-rfc-8259 does not directly conform `RFC_8259.Value` to `Hash.Protocol`; the witness primitives' direct value to this design is the integration-bridge `String: Hash.Protocol`. The fuller witness-primitive payoff requires `RFC_8259.Value: ~Copyable` (= L2). On L1, the primitives are dep-graph load-bearing but not API load-bearing. This is an honest framing of where the witness investment fires. |

### 8. What this design does NOT do

- Does NOT change `RFC_8259.Value` enum or its Copyable / Sendable / Hashable conformances.
- Does NOT change `RFC_8259.Array._storage: [Value]` — Array indexed access is already O(1); no benefit to changing.
- Does NOT change the public `JSON` dynamic-member-lookup surface (`json.user.name.string` works as today).
- Does NOT touch the parent-session blocklist (`Parser.Input.swift`, `Parser.Tracked.swift`, `swift-json/.gitignore`, `swift-rfc-8259/.github/metadata.yaml`).
- Does NOT introduce any new ecosystem primitive — [DS-020] and [RES-018] are respected. `Dictionary.Ordered` exists; we consume it.
- Does NOT introduce `import Foundation` in `Sources/` of either package.
- Does NOT change the typed-throws contract on parser surfaces.
- Does NOT propose `Buffer.Arena` Option A as a precondition. That arc is independent.
- Does NOT close the tree-teardown wedge. Lookup is the priority; teardown is the conditional follow-on if a teardown-dominated workload surfaces.

### 9. Out of scope (deferred to future arcs)

- **L2 (`~Copyable` Value tree, arena-bound)** — DEFERRED per §6 Phase L2; re-opens only with second consumer + Buffer.Arena Option A landed.
- **L3 (hybrid small/large)** — DEFERRED; re-opens if L1-2 measurement shows constant-factor losses on small-object lookups.
- **L4 (lazy index)** — REJECTED; structurally worse than L1 for the same gain.
- **`JSON.Serializable` redesign for v2** — Out of scope; the protocol survives L1 unchanged.
- **`JSON.parse.prepared()` / `.located()` redesign** — Out of scope; these signatures survive L1 unchanged.
- **`JSON.ND.stream` redesign** — Out of scope; the streaming API survives L1 unchanged.
- **Migration of `RFC_8259.Array._storage` to a typed primitive** — Out of scope; current `[Value]` storage already gives O(1) indexed access.
- **Promotion of any new abstraction to `swift-json-primitives` or similar** — Out of scope; v2's storage choices live inside `swift-rfc-8259`.

## Outcome

**Status**: RECOMMENDATION.

**Recommended architecture**: **L1 — Replace `RFC_8259.Object._storage` with `Dictionary<String, RFC_8259.Value>.Ordered`** from `swift-dictionary-primitives`. Keep `RFC_8259.Value` enum and `RFC_8259.Array` shape unchanged. Public API surface stable. Witness primitives consumed transitively via `Hash Primitives Standard Library Integration` (provides `String: Hash.Protocol` under Swift 6.3 fork; typealias under Swift 6.4+).

**Projected lookup performance vs Foundation**: matches or modestly beats on the symbol-graph oracle's traversal pattern. Confidence: **medium-high** — the underlying `Hash.Table` is open-addressed power-of-two-sized with linear probing, the same shape `NSDictionary` uses; the institute's stays-in-typed-Swift path avoids the `Any`-bridge cost. The principal-named workload should see ≥ 20 % total-throughput improvement on the lookup-heavy reduce path. **Honest framing: the per-call latency is not radically better than Foundation; the architectural win is the absence of `[String: Any]` bridge and O(1) vs O(n) scaling on growing objects.**

**Projected parse performance**: modest regression from A1's 1.02× Foundation baseline, to ~1.15×–1.25× — **acceptable, well under the 1.3× target from the predecessor arc**. Reasoning: per-member `Dictionary.Ordered.set` costs more than `Array.append`, but the cost is proportional to key count per object (~6 for the canonical workload). The bench harness extension in L1-0 makes this measurable before commit.

**Phased landing plan**:

- **Phase L1-0** (½ day): Pre-A0 verification — `String: Hash.Protocol` integration bridge under Swift 6.3 + 6.4-dev; microbench Dictionary.Ordered vs Swift.Dictionary at 6-key workload; add `lookup` mode to `Experiments/parse-performance-bench`.
- **Phase L1-1** (3–5 days): Replace `RFC_8259.Object._storage`, rewrite Iterator, adjust parser. All 124 tests green. New bench numbers recorded.
- **Phase L1-2** (measurement gate): bench results determine v2.0.0 disposition.
- **Phase L1-3** (½ day, conditional): public-API cleanup of `JSON.dictionary` if the survey calls for it.
- **Phase L2 (DEFERRED)**: conditional follow-on per `parse-performance-architecture.md` §5; re-opens only with second hot consumer + Buffer.Arena Option A landed.

**Migration story for downstream consumers**: zero public-API break. `Object[key]?.string`, `for (k, v) in obj.object!`, `json.user.name.string`, `JSON.parse.prepared()`, `JSON.parse.located()`, `JSON.ND.stream`, `JSON.Serializable`, `[String: JSON]` literals, dynamic-member-lookup chains — all survive byte-identical. The only consumer-visible difference is that `Object[key]` is now O(1) instead of O(n) — a strict improvement. If `JSON.dictionary` is deprecated in L1-3, consumers can migrate to `JSON.object` (existing accessor); SemVer-MAJOR is justifiable if any change to that accessor lands, but most downstream code uses the dynamic-member-lookup chain rather than `.dictionary` directly.

## References

### Predecessors

- `swift-foundations/swift-json/Research/parse-performance.md` v1.2.0 — Parse-side parity arc; established the post-A1 wedge breakdown that this arc takes as input.
- `swift-foundations/swift-json/Research/parse-performance-architecture.md` v1.0.2 — Span-specialized lexer; §5 conditional Phase B clause that this arc implicitly re-frames.

### Prior art (institute Research)

- `swift-institute/Research/buffer-arena-conditional-copyable.md` v1.1.0 — Buffer.Arena conditional-Copyable constraint; load-bearing on the L2 deferral.
- `swift-institute/Research/comparative-dictionary-primitives.md` v1.0.0 — Dictionary catalog; gap-list (Hash.Protocol bridging, `subscript(default:)`, `removeAll(where:)`) relevant for any future swift-json work that goes beyond Object's read API.
- `swift-institute/Research/ecosystem-data-structures-inventory.md` — Cross-package catalog confirming Dictionary.Ordered's fit.

### Prior art (per-package Research)

- `swift-primitives/swift-dictionary-primitives/Research/value-storage-buffer-layering.md` — Dictionary.Ordered's `_keys + _values` 1:1 paired shape, the architectural pattern this arc consumes.
- `swift-primitives/swift-dictionary-primitives/Research/dictionary-removal-strategies.md` — Background for any future `removeAll(where:)` need.
- `swift-primitives/swift-hash-table-primitives/Research/hash-table-storage-buffer-layering.md` — Open-addressed hash table internals; basis for the lookup-throughput projection.

### Current parser surface

- `swift-ietf/swift-rfc-8259/Sources/RFC 8259/RFC_8259.Object.swift:21-37, 73-88, 138-156` — Today's `_storage: [(String, Value)]` declaration and O(n) subscript with explicit doc-comment acknowledging the cost.
- `swift-ietf/swift-rfc-8259/Sources/RFC 8259/RFC_8259.Object.Iterator.swift:1-22` — Today's iterator (wraps `IndexingIterator` over `[(String, Value)]`).
- `swift-ietf/swift-rfc-8259/Sources/RFC 8259/RFC_8259.Value.swift:30-49` — `RFC_8259.Value` enum, Sendable + Hashable.
- `swift-ietf/swift-rfc-8259/Sources/RFC 8259/RFC_8259.Array.swift:29-43` — `RFC_8259.Array._storage: [Value]` (unchanged in L1).
- `swift-ietf/swift-rfc-8259/Sources/RFC 8259/RFC_8259.Parser.Span.swift` — Span parser that builds Object via `Object.init(_:)`.
- `swift-foundations/swift-json/Sources/JSON/JSON.swift:182-189` — `JSON.dictionary: [String: JSON]?` accessor that builds an ad-hoc `Swift.Dictionary` per access.
- `swift-foundations/swift-json/Sources/JSON/JSON.swift:199-213` — `JSON` subscripts (key + index) that route through `Object[key]` / `Array[i]`.
- `swift-foundations/swift-json/Sources/JSON/JSON.Parse.swift:23-269` — Public parse API (preserved verbatim).
- `swift-foundations/swift-json/Sources/JSON/JSON.Stream.swift:23-264` — Streaming API (preserved verbatim).
- `swift-foundations/swift-json/Sources/JSON/JSON.Serializable.swift:1-279` — Serializable protocol (preserved verbatim).
- `swift-foundations/swift-json/Experiments/parse-performance-bench/Sources/parse-performance-bench/main.swift:99-232` — Bench harness; new `lookup` mode lands here in L1-0.

### Candidate storage primitives

- `swift-primitives/swift-dictionary-primitives/Sources/Dictionary Primitives Core/Dictionary.Ordered.swift:80-119` — `Dictionary<K: Hash.Protocol, V: ~Copyable>.Ordered` declaration; conditional Copyable.
- `swift-primitives/swift-dictionary-primitives/Sources/Dictionary Primitives Core/Dictionary.Ordered Copyable.swift:119-156` — O(1) keyed subscript (the path swift-json's `Object[key]` would call into).
- `swift-primitives/swift-set-primitives/Sources/Set Primitives Core/Set.swift:36-101` — `Set<E: Hash.Protocol>.Ordered` (Buffer.Linear + Hash.Table composition); the building block of Dictionary.Ordered's `_keys`.
- `swift-primitives/swift-hash-table-primitives/Sources/Hash Table Primitives Core/Hash.Table.swift:20-138` — Open-addressed hash table; the lookup engine behind Dictionary.Ordered.
- `swift-primitives/swift-hash-primitives/Sources/Hash Primitives Core/Hash.Protocol.swift:1-94` — `Hash.Protocol` (typealias to Swift.Hashable on 6.4+, fork on <6.4).
- `swift-primitives/swift-equation-primitives/Sources/Equation Primitives Core/Equation.Protocol.swift:1-91` — Same pattern.
- `swift-primitives/swift-memory-primitives/Sources/Memory Arena Primitives/Memory.Arena.swift:1-153` — Memory.Arena (used only in conditional L2 follow-on; included for reference).

### Skill references

- [API-NAME-001], [API-NAME-014] — Naming (RFC_8259.Object stays as Object; Swift.Dictionary vs Dictionary_Primitives_Core.Dictionary disambiguated via module-qualified import where necessary).
- [API-ERR-001] — Typed throws on all throwing surfaces (preserved).
- [API-IMPL-005] — One type per file (Object.swift, Object.Iterator.swift unchanged in count).
- [PRIM-FOUND-001], [ARCH-LAYER-007] — Foundation-free in Sources/ (preserved).
- [ARCH-LAYER-001], [ARCH-LAYER-011] — Dependency direction; this arc takes one new dep edge (L2 swift-rfc-8259 → L1 swift-dictionary-primitives), consistent with layer rules.
- [ARCH-LAYER-008] — Correctness-driver pre-1.0; ship the right architecture for the current evidence rather than waiting for a richer architecture's prerequisites to land.
- [MOD-015] — Consumer import precision; narrow `Dictionary Ordered Primitives` import rather than the umbrella.
- [DS-001], [DS-003], [DS-005], [DS-020] — Ecosystem data-structures; Dictionary.Ordered consumed, no new primitive proposed.
- [MEM-COPY-001], [MEM-SAFE-001], [MEM-SAFE-020] — Memory safety preserved; Dictionary.Ordered is `@safe`.
- [IMPL-INTENT], [IMPL-COMPILE], [IMPL-002] — Typed arithmetic at the public boundary, mechanism encapsulated in the storage primitive.
- [RES-003], [RES-010b], [RES-018], [RES-019], [RES-021], [RES-027] — Research process; option-comparison, second-consumer hurdle (no new primitive proposed, only consumption), prior-art grep, loose-end follow-up empirical verification (L1-0's bench-mode addition).
- [BENCH-001], [BENCH-002] — Bench placement (extend existing harness in `Experiments/`; clean `.build` between runs).
- [HANDOFF-013] — Prior-research grep performed (results captured in §1).

## Provenance

Investigation invoked via supervisor dispatch following the parse-performance Tier-4 arc's A2 measurement gate (passed; tree-side wedge identified but deferred). Scope: design swift-json v2's value-tree architecture optimised for O(1) lookup as the primary deliverable, with secondary leverage on the institute's witness-protocol primitives. The architecture recommended here lands inside `swift-rfc-8259` via a single dep on `swift-dictionary-primitives`; the public swift-json surface stays byte-identical (no break for downstream); witness-primitive load-bearing is acknowledged honestly as transitive-through-Dictionary rather than direct-on-Value. The L2 arena follow-on stays parked behind the conditional clause from the predecessor's `parse-performance-architecture.md` §5, re-opening only with a second hot consumer and a landed `Buffer.Arena: Copyable when Element: Copyable`. The blocklist of four uncommitted files at the parent session boundary (`Parser.Input.swift`, `Parser.Tracked.swift`, `swift-json/.gitignore`, `swift-rfc-8259/.github/metadata.yaml`) was treated as read-only.
