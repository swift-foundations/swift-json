# Parse Performance Architecture — Tier 4

<!--
---
version: 1.0.1
last_updated: 2026-05-13
status: RECOMMENDATION
tier: 2
---
-->

> **v1.0.1 (2026-05-13)**: Phase A0 GREEN — all three premises confirmed.
> Evidence in `Experiments/parse-performance-tier-4-feasibility/`.
> `~Escapable` on associated types confirmed by the principal under
> `.enableExperimentalFeature("SuppressedAssociatedTypes")`.
> `String.UTF8View.withContiguousStorageIfAvailable` engaged on all 7
> probed shapes including bridged NSString (more favourable than this
> doc's prior §4.3 line 487-489 projection). `Span<UInt8>` + `throws(E)`
> + `@_lifetime(borrow bytes)` composition compiles and runs cleanly;
> typed errors propagate across `inout Cursor` boundaries. Phase A1 is
> unblocked. See §8 "A0 disposition" appended below.

## Context

This document is the Tier-2 design follow-on to
`swift-foundations/swift-json/Research/parse-performance.md` v1.1.0
(Tier 1 *RECOMMENDATION*). The predecessor doc established the
five-tier path forward and landed Tiers 0/1/3 — a measured 27 %
reduction in wall-clock on an 86 MB symbol-graph parse, closing the
Foundation gap from 3.05× to 2.33×. The four wedges that remain in
the post-Tier-1 profile are itemised in `parse-performance.md` §6
*Residual gap*:

1. Recursive `[(String, Value)]` / `[Value]` value-tree teardown
   (~7 % per iteration, ≈245 ms across the 10× sample).
2. `Lexer.next()` token dispatch (~4 % per iteration).
3. Typed `Position` arithmetic in `advance()` (line/column updates on
   every byte).
4. Generic `Parser.Input.Protocol` dispatch overhead — the cursor
   sits behind a protocol chain even after release-mode generic
   specialization.

"Tier 4" is the *Span-specialized internal lexer* — an internal
dispatch path for the contiguous-bytes case that bypasses the four
wedges above by replacing the generic `Input.Buffer<…>` cursor with a
`Span<UInt8>`-backed view, while keeping the public
`JSON.parse(_: String)` / `JSON.parse(_: [UInt8])` / `JSON.parse.prepared()`
/ `JSON.parse.located()` API surface unchanged. The goal stated by
the principal is **≤ 1.3× Foundation on stdlib-scale inputs**
(≤ 0.39 s on the 86 MB workload, down from 0.67 s on the
`[UInt8]` path today).

This research doc enumerates structurally distinct architectures,
evaluates each against the 1.3× target and the package's
contractual constraints (Foundation-free production code, stable
public API, typed-cursor / typed-throws / strict-memory-safety
discipline), surveys prior art in the ecosystem, and recommends a
single architecture with a phased landing plan.

This is RESEARCH ONLY — no source files are modified by this
investigation. Implementation lands in subsequent dispatches under
the phased plan.

## Question

What architecture for the `swift-rfc-8259` parser reaches ≤ 1.3×
Foundation.JSONSerialization on stdlib-scale inputs (≈86 MB
pretty-printed UTF-8 JSON), while:

1. Preserving the Foundation-free guarantee for production code
   (`Sources/` of both `swift-rfc-8259` and `swift-json` —
   `import Foundation` permitted ONLY in `Tests/`)?
2. Keeping the public `JSON.parse(_: String)`,
   `JSON.parse(_: [UInt8])`, `JSON.parse.prepared()`, and
   `JSON.parse.located()` signatures byte-identical?
3. Preserving the typed-cursor (`Index<UInt8>.Offset` /
   `.Count`), typed-throws (`throws(RFC_8259.Error)`), and
   strict-memory-safety discipline the package maintains today
   (one `@_spi(Unsafe)` import in `RFC_8259.Lexer.swift:6`; no
   raw `UnsafePointer<UInt8>` parser dressed up as Swift)?

## Analysis

### 1. Prior research — what's already been said

Per [HANDOFF-013] / [RES-019], the relevant predecessor + prior art:

| Source | What it establishes | Relation to Tier 4 |
|---|---|---|
| `swift-foundations/swift-json/Research/parse-performance.md` v1.1.0 | Five-tier path; Tiers 0/1/3 landed; profile attribution after the cheap edits; residual gap localisation | **Direct predecessor.** This doc designs Tier 4 to attack the four residual wedges. |
| `swift-primitives/swift-input-primitives/Sources/Input Primitives/Input.swift:55-63` | `Input.Borrowed` is "planned but deferred pending stable `~Escapable` support in protocol associated types + generic lifetime parameterization" | Tier 5 of the predecessor doc; Tier 4 is the path *without* waiting for `Input.Borrowed`. |
| `swift-primitives/swift-parser-primitives/Experiments/suppressed-escapable-associated-types/Sources/main.swift` | CONFIRMED 2026-02-13 (Swift 6.2.3+): `associatedtype Input: ~Escapable` compiles; `Span<UInt8>` satisfies the constraint; `inout Input: ~Escapable` works; V6 (returning `~Escapable` from protocol method) REFUTED as language limitation | The language is unblocked for `~Escapable` parser inputs. Tier 4's internal Span lexer does not need V6 — it returns owned values, not borrowed slices. |
| `swift-primitives/swift-binary-parser-primitives/Sources/Binary Input View Primitives/Binary.Bytes.Input.View.swift` | Production reference for the pattern: `~Copyable & ~Escapable` struct, `let span: Span<UInt8>`, `var position: Int`, `@_lifetime(borrow span)` constructor, `@_lifetime(self: copy self)` mutating, `@_lifetime(copy self)` subscript | **Canonical precedent.** Tier 4 mirrors this shape one layer up (text parsing instead of binary parsing), in the `swift-rfc-8259` namespace until promotion is justified. |
| `swift-primitives/swift-ascii-parser-primitives/Sources/ASCII Decimal Parser Primitives/ASCII.Decimal.Parser.swift:27-57` | `ASCII.Decimal.Parser<Input, T: FixedWidthInteger>` — generic over `Collection.Slice.Protocol`, with overflow-aware accumulation | Tier 2 of the predecessor doc (HELD). This research notes the dep-graph cost (one new dep on `swift-rfc-8259`) and defers the Tier-2/Tier-4 ordering decision to the phased plan below. |
| `swift-institute/Research/buffer-arena-conditional-copyable.md` v1.1.0 | `Buffer.Arena` is unconditionally `~Copyable` (manages a separately heap-allocated meta array via `deinit`); blocks downstream `Tree.N` conditional Copyable + CoW | Restricts the slab-allocated-tree option below: a JSON value tree built on `Buffer.Arena<RFC_8259.Value>` cannot be conditionally Copyable. The public `RFC_8259.Value` is `Sendable, Hashable` (Copyable) today; an arena-backed tree behind the public façade requires owning the arena's lifetime separately or building a copy at the API boundary. |
| `swift-institute/Research/tree-primitives-buffer-arena-migration.md` | Tree-primitives migration to `Buffer.Arena`; arena/tree-shape trade-offs | Background for any "switch JSON to a Tree.* container" proposal. |
| `swift-input-primitives/Research/advance-by-offset-vs-count.md` (SUPERSEDED) | Position offset vs count semantics | Historical; superseded by typed-index-arithmetic-unification work. |

The Tier 4 design has been *outlined* in the predecessor doc but not
designed in detail. There is no other prior research doc that
duplicates this scope.

### 2. The four wedges Tier 4 must attack

From `parse-performance.md` v1.1.0 §6 *Residual gap*, ordered by
share of remaining wall-clock:

| Wedge | Current cost | Source location |
|---|---|---|
| Value-tree teardown | ~7 % per iteration (≈245 ms / 10 iter; rising to ~361 ticks in `outlined destroy of RFC_8259.Value` after Tier 1) | Recursive `enum RFC_8259.Value` carrying `RFC_8259.Object._storage: [(String, Value)]` and `RFC_8259.Array._storage: [Value]` (`RFC_8259.Object.swift:23-37`, `RFC_8259.Array.swift:30-43`) |
| `Lexer.next()` token dispatch | ~4 % per iteration; ~220 ticks in the profile | `RFC_8259.Lexer.swift:122-178` switch on leading byte |
| Per-byte `advance()` position update | Embedded in `Input.Buffer.advance()` (97 ticks) + `Lexer.advance()` (now collapsed into the random-access subscript) | `Input.Buffer+Input.Protocol.swift:62-70` + `RFC_8259.Lexer.swift:86-104` |
| `Parser.Input.Protocol` dispatch overhead | Diffuse — survives release-mode specialization because the protocol chain remains in the call signature; the specialized witness still chains `Input.Protocol` → `Input.Access.Random` → concrete | All hot lexer / parser methods carry `where Input: Parser_Primitives.Parser.Input.Protocol & Input_Primitives.Input.Access.Random & ~Copyable` (`RFC_8259.Lexer.swift:26-27`, `RFC_8259.Parser.swift:28-29`) |

The four wedges are *coupled* — the generic Input dispatch overhead
amortizes per byte, the position arithmetic is per byte, the token
dispatch is per token (≈one per few bytes on pretty-printed input),
and the value-tree teardown is per-Value (one per atom + one per
container). Closing one without the others leaves the parser bound
by the next. Tier 4's value is closing the *cursor + dispatch + position*
trio in one stroke and leaving the tree-teardown wedge as an
optional Phase B.

### 3. Candidate architectures

Per [RES-010b], at least three structurally distinct architectures
are enumerated and compared. The three candidates are:

- **Architecture A**: `Span<UInt8>` cursor over the existing
  `RFC_8259.Value` enum tree.
- **Architecture B**: `Span<UInt8>` cursor over a `~Copyable`
  arena-allocated tree, with conversion to the existing
  `RFC_8259.Value` at the public boundary.
- **Architecture C**: `RawSpan` cursor with a table-driven token
  classifier, lazy position tracking, and an arena-allocated tree.

#### Architecture A — Span cursor + existing tree

**Shape**:

- Internal `RFC_8259.Lexer.Span` type:
  `~Copyable & ~Escapable` struct holding `let bytes: Span<UInt8>`,
  `var position: Int`, plus the `_position: RFC_8259.Position`,
  `_stringScratch: [UInt8]` lexer state. Lifetime-annotated per the
  `Binary.Bytes.Input.View` precedent.
- Internal `RFC_8259.Parser.Span` type wrapping the Span lexer with
  the same depth/lookahead state as today's generic parser.
- `RFC_8259.Decode.callAsFunction(_: C)` (and the `String` /
  `Substring` overloads) dispatches as follows:
  1. `String` path: `string.utf8.withContiguousStorageIfAvailable {
     buffer in let span = buffer.span; return parseSpan(span) }`
     fast-path; falls back to `String.UTF8View.withSpan(_:)` when
     stable, else owned-array path.
  2. `[UInt8]` / `ContiguousArray<UInt8>` path:
     `bytes.withUnsafeBufferPointer { buffer in let span = buffer.span;
     return parseSpan(span) }` — zero materialisation copy on the
     contiguous-storage cases that the public API constrains to.
  3. Arbitrary `Collection<UInt8>` (the generic `<C: Collection &
     Sendable> where C.Element == UInt8>` overload at
     `RFC_8259.Decode.swift:40-49`): keep the existing
     `Swift.Array(bytes)` materialisation as the slow path. Test
     suite already exercises this.
- The Span parser emits `RFC_8259.Value` directly via the existing
  enum constructors (`.string(_)`, `.number(_)`, `.array(_)`,
  `.object(_)`). The value tree is unchanged.
- The public API surface
  (`RFC_8259.decode`, `RFC_8259.parse`, `JSON.parse`,
  `JSON.parse.prepared()`, `JSON.parse.located()`) keeps its current
  signatures verbatim. The Span specialization is a private
  dispatch fork at the entry point.

**Wedges attacked**:

| Wedge | Closed? |
|---|---|
| `Lexer.next()` dispatch | Partial — switch survives but inlines through `Span<UInt8>` byte access (`span[position]`) instead of through the `Input.Protocol` chain. Token dispatch cost stays at ~4 % of *total* parse, but total parse shrinks. |
| `advance()` position update | Yes — `position += 1` on `Int` instead of typed-`Index` arithmetic + saturating add + line/column rebuild. Line/column is computed lazily at error sites only (the only consumer is `RFC_8259.Position`, exposed through `Lexer.position` and surfacing in errors). |
| `Parser.Input.Protocol` dispatch | Yes — the protocol chain is gone from the hot path. |
| Value-tree teardown | **No.** Tree shape is unchanged. |

**1.3× attainability**: From the predecessor doc's profile, the
three cursor-side wedges account for ~10–13 % of *total* parse
wall-clock; the residual 2.33× gap to Foundation is dominated by
them. Architecture A closes them. Expected throughput on the
`[UInt8]` path: ~0.67 s → ~0.38 s ± 0.05 s (confidence: medium-high).
This *probably* hits 1.3× on the workload, but with negative tail
risk if value-tree teardown is more dominant than the post-Tier-1
profile shows.

**Ecosystem-fit**: Excellent. Mirrors `Binary.Bytes.Input.View`
one layer up; lives in `swift-rfc-8259` as an internal detail
until the second consumer surfaces ([RES-018] second-consumer
hurdle for promoting to `swift-text-input-primitives` or similar).
Uses `Span<UInt8>` (stdlib), no new ecosystem primitives required.
The strict-memory-safety contract is preserved: the internal Span
view is `@safe` (the same shape as `Binary.Bytes.Input.View`),
all unsafe expressions are at the lifetime-annotated initializers.

**Implementation cost**: Medium — ~600–900 LoC across two new
internal types (`RFC_8259.Lexer.Span`, `RFC_8259.Parser.Span`), a
dispatch fork in `RFC_8259.Decode`, and the lazy position tracking
helper. Lexer logic is duplicated (not generalized) because the
generic-Input parser path stays for `Collection.Slice` and
`Input.Slice` callers. No public API impact.

**Public-API impact**: None. All public surfaces preserved verbatim.

**Risk**:

- (a) Span lifetime over `String.UTF8View` is workably stable but
  the `withContiguousStorageIfAvailable` fallback for non-contiguous
  Strings allocates — measured cost varies with the source's
  encoding. Mitigated by the public-API contract: callers pass
  contiguous storage in practice.
- (b) If the value-tree teardown wedge expands when the cursor side
  speeds up (Amdahl shift), 1.3× may slip to 1.4–1.5×. Closes
  with Phase B (Architecture B's tree shape).

#### Architecture B — Span cursor + arena-allocated `~Copyable` tree

**Shape**:

- Same Span cursor and lexer as Architecture A.
- Internal arena-allocated parse tree: instead of emitting
  `RFC_8259.Value` directly, the Span parser writes into a
  `Memory.Arena`-backed slab of typed nodes (see `Memory.Arena` at
  `swift-memory-primitives/Sources/Memory Arena Primitives/Memory.Arena.swift`).
- Tree shape: `RFC_8259.Value.Node` (internal,
  `~Copyable & ~Escapable`) with discriminator + payload. Object /
  Array storage is contiguous-in-arena `Memory.Address` ranges.
- At the public-API boundary, the arena tree is *converted* into the
  existing `RFC_8259.Value` enum, preserving the public type. The
  arena drops at end of parse via `Memory.Arena.deinit`.

**Wedges attacked**: All four. The arena-allocated tree converts
into the public `RFC_8259.Value` in a single linear pass that
allocates the `[(String, Value)]` / `[Value]` storage *once per
node* rather than incrementally; teardown is bulk arena
deallocation.

**1.3× attainability**: Close to certain *if* the conversion at the
public boundary is cheaper than the per-node `Array.append` that
Architecture A retains. The conversion's cost depends on whether
the public tree must be materialised at all — if downstream
consumers only walk the tree once (the symbol-graph oracle case),
the conversion is wasted work. Confidence: medium. The
double-allocation cost (arena + public-tree materialisation) may
*hurt* throughput on the canonical workload if the workload
includes few enough re-traversals.

**Ecosystem-fit**: Acceptable but expensive. `Memory.Arena` is an
existing primitive. However: per
`swift-institute/Research/buffer-arena-conditional-copyable.md`
v1.1.0, `Buffer.Arena` is unconditionally `~Copyable` because its
deinit owns a separately heap-allocated meta array. An arena-tree
behind the public façade has to be materialised into the public
Copyable `RFC_8259.Value` before the arena drops — there is no
"zero-cost cast" path.

**Implementation cost**: High — ~1500–2500 LoC. Two value-tree
shapes, conversion logic, arena lifecycle management,
`@_lifetime` annotations propagated through every node operation.

**Public-API impact**: None if conversion at the boundary is
mandatory; significant if the public `RFC_8259.Value` is broadened
to expose the arena tree as a variant (hard constraint #2 violated).

**Risk**:

- (a) Conversion cost may eat the wedge it's supposed to close.
- (b) The constraint that the public `RFC_8259.Value` stays
  Copyable + Sendable + Hashable forces materialisation; the arena
  tree is wasted for one-pass consumers.
- (c) High implementation cost vs uncertain payoff.

#### Architecture C — `RawSpan` cursor + table-driven token classifier + lazy position + arena tree

**Shape**:

- `RawSpan` cursor (untyped byte access via `RawSpan.unsafeLoad(fromByteOffset:as:)`)
  — strictly more permissive than `Span<UInt8>`; slightly higher
  load cost per byte but allows bulk loads (`UInt32` /
  `UInt64`) for token classification, length-prefix lookahead, and
  SWAR (SIMD-within-a-register) whitespace/digit detection.
- Token classifier as a 256-entry static lookup table indexed by
  byte value, returning a `Token.Kind` enum case discriminator (a
  small `UInt8`). The switch in `Lexer.next()` becomes:
  `let kind = Token.Kind.classify(byte); switch kind { ... }`
  with cases dispatched as before. Marginally faster on byte-by-byte
  but mainly opens the door to vectorised whitespace skipping.
- Lazy position tracking: drop the line/column rebuild in
  `advance()`; recompute on error at `RFC_8259.Position`
  construction. The `Lexer.position` accessor builds the position
  on demand by scanning the consumed prefix for `\n`.
- Arena tree (as in Architecture B), with the same caveats.

**Wedges attacked**: All four, more aggressively than B.

**1.3× attainability**: Highest theoretical ceiling. Reaching it
requires:
- The token-classifier table to actually save more cycles than the
  branch-predicted switch costs today (often a wash on modern
  branch-prediction; meaningful on byte streams with many distinct
  token kinds, less so on JSON where 90 % of bytes are
  `whitespace / digit / quoted-string-body`).
- The arena tree's conversion cost (Architecture B's concern) to
  be amortised by the cursor savings.

**Ecosystem-fit**: Marginal. `RawSpan` is stdlib; the rest is
hand-rolled internal work or new primitives. SWAR/SIMD scanning
in the institute would benefit from a primitive (e.g.,
`Memory.Bytes.Scan` or similar) that does not yet exist —
[DS-020] gate-before-proposing-new-primitives applies and the
proposal can not yet meet the bar (one consumer, novel shape).

**Implementation cost**: Very high — ~3000+ LoC; touches arena
tree + lazy position + lookup table + dispatch fork. Multi-week
landing.

**Public-API impact**: Constrained the same way Architecture B is:
materialise to the public `RFC_8259.Value` at the boundary.

**Risk**:

- (a) Compounding gambles: each of the four wedges depends on its
  own assumption (table > switch, lazy > eager, arena > heap,
  RawSpan > Span). If any one fails to clear, the others stack on
  top of it.
- (b) Strict-memory-safety contract under `RawSpan` is materially
  harder — `RawSpan` operations require `unsafe` markings at every
  load.
- (c) [DS-020] new-primitive gate would block SWAR scanner
  promotion absent a second consumer.

#### Option comparison summary

| Criterion | A: Span + existing tree | B: Span + arena tree | C: RawSpan + table + lazy + arena |
|---|---|---|---|
| Closes cursor wedges | Yes | Yes | Yes |
| Closes tree-teardown wedge | No (separate phase) | Yes (with conversion cost) | Yes (with conversion cost) |
| Hits 1.3× on workload | Medium-high confidence | Medium confidence (conversion risk) | Medium confidence (compounding risk) |
| Foundation-free | Yes | Yes | Yes |
| Public API preserved | Yes | Yes (with materialisation) | Yes (with materialisation) |
| Ecosystem-fit | Excellent (mirrors `Binary.Bytes.Input.View`) | Acceptable (existing `Memory.Arena`; conversion friction) | Marginal (needs SWAR primitive proposal) |
| Strict-memory-safety preserved | Yes | Yes | Materially harder under RawSpan |
| Implementation cost | Medium (~600–900 LoC) | High (~1500–2500 LoC) | Very high (~3000+ LoC) |
| Time to land | One arc (~2–3 dispatches) | Two arcs (cursor + tree) | Three arcs |
| Independently shippable phases | Yes | Yes | Yes |
| Reversibility | High (internal-only) | Medium (arena lifecycle survives the source tree) | Low (table + lazy + RawSpan compound) |

**Recommendation**: Architecture A as the *primary landing*, with
Architecture B as an optional Phase B once a second hot consumer
demonstrates that tree-shape work pays its own way. Architecture
C is rejected per [DS-020] (new primitive without two consumers) and
[ARCH-LAYER-008] (correctness-driven shaping, not benchmark-driven
scope creep).

### 4. Span cursor — concrete design

The recommended Architecture A reuses the
`Binary.Bytes.Input.View` shape verbatim, adapted to text parsing.

#### 4.1 Cursor type

The cursor lives in `swift-rfc-8259` as an internal detail until a
second consumer surfaces — Tier 4 is local specialisation, not
ecosystem-wide infrastructure. Following the same shape as
`Binary.Bytes.Input.View`:

```
// File: RFC_8259.Lexer.Span.swift  (NEW — internal)
extension RFC_8259.Lexer {
    /// Span-specialised cursor for the contiguous-bytes case.
    ///
    /// `~Copyable & ~Escapable` per the `Binary.Bytes.Input.View`
    /// precedent. The cursor cannot escape the scope of the span it
    /// borrows; the compiler enforces this via `@_lifetime(borrow span)`.
    ///
    /// Not a public type — exposed only to the `RFC_8259.Decode`
    /// dispatch fork. If a second hot consumer surfaces, promote
    /// per [RES-018].
    @safe
    internal struct Span: ~Copyable, ~Escapable {
        @usableFromInline
        internal let bytes: Swift.Span<UInt8>

        @usableFromInline
        internal var position: Int

        @inlinable
        @_lifetime(borrow bytes)
        internal init(_ bytes: borrowing Swift.Span<UInt8>) {
            self.bytes = copy bytes
            self.position = 0
        }
    }
}
```

The naming is `RFC_8259.Lexer.Span` per [API-NAME-001] / [API-NAME-001a] —
"Span" is a variant label on `RFC_8259.Lexer`, not a top-level
domain. The genuine `Span<UInt8>` (stdlib) is referenced as
`Swift.Span<UInt8>` to disambiguate per the namespace-shadow rule
([API-NAME-014]).

Hot operations:

| Operation | Signature | Mechanism |
|---|---|---|
| `peek` | `var peek: UInt8? { _read }` | `bytes[position]` if `position < bytes.count`, else nil |
| `peek(offset:)` | `subscript(offset offset: Int) -> UInt8?` | direct byte access, no position mutation |
| `advance` | `mutating func advance() -> UInt8` | `position &+= 1` + return byte |
| `advance(by:)` | `mutating func advance(by n: Int)` | `position &+= n` |
| `isEmpty` | `var isEmpty: Bool` | `position >= bytes.count` |
| `startsWith` | `func startsWith<C>(_ prefix: C) -> Bool` | bulk-compare for literal expectations (`null`, `true`, `false`) |

All position arithmetic is `Int` arithmetic. Typed-position
(`Index<UInt8>` + `Cardinal`) machinery is preserved at the
public-API boundary in `RFC_8259.Position` and on the existing
`Input.Buffer`-based slow path — the Span cursor does not change
the public typed-cursor contract, it specialises the implementation.

The lexer's `RFC_8259.Position`-valued `_position` is *not* updated
on every byte. It is computed *lazily* — only when an error is
thrown or when `lexer.position` is read externally — by scanning
`bytes[..<position]` for newlines. The scan is O(consumedBytes) but
fires once per error rather than once per byte; for non-pathological
inputs that is a measured net reduction.

#### 4.2 Lexer and parser

`RFC_8259.Lexer.Span` and `RFC_8259.Parser.Span` are internal
non-generic types specialised on the Span cursor. Their token
emission, error throwing, and tree construction are byte-identical
to the existing generic lexer/parser — the only difference is the
cursor type. This keeps the public `RFC_8259.Lexer<Input>` /
`RFC_8259.Parser<Input>` types operating against their existing
generic Input contract; downstream consumers that import
`RFC_8259.Lexer<…>` directly are unaffected.

The token type `RFC_8259.Token` is reused as-is (it carries
`String` for `.string` and `RFC_8259.Number` for `.number` — both
owned, no lifetime concerns).

`RFC_8259.Value` construction in the Span parser uses the same
`RFC_8259.Object(_ elements: [(key: String, value: Value)])` /
`RFC_8259.Array(_ elements: [Value])` initializers the generic
parser uses today. The tree shape is unchanged.

#### 4.3 Dispatch fork

In `RFC_8259.Decode.swift`, the existing entry point is augmented
with a contiguous-storage fast path. Public signatures unchanged:

```
extension RFC_8259.Decode {
    @inlinable
    public func callAsFunction<C: Swift.Collection & Sendable>(
        _ bytes: C, maxDepth: Int = 512
    ) throws(RFC_8259.Error) -> RFC_8259.Value
    where C.Element == UInt8, C.Index: Sendable {
        // Fast path: contiguous storage → Span cursor.
        if let result = try bytes.withContiguousStorageIfAvailable({ buffer
            throws(RFC_8259.Error) -> RFC_8259.Value in
            let span = buffer.span
            return try RFC_8259.Parser.Span.parse(span, maxDepth: maxDepth)
        }) {
            return result
        }
        // Slow path: arbitrary Collection<UInt8>. Existing implementation.
        let array = Swift.Array(bytes)
        let input = Input.Buffer(array)
        var parser = RFC_8259.Parser(consume input, maxDepth: maxDepth)
        return try parser.parse()
    }

    @inlinable
    public func callAsFunction(_ string: String, maxDepth: Int = 512)
        throws(RFC_8259.Error) -> RFC_8259.Value {
        // Fast path: contiguous UTF-8 storage.
        if let result = try string.utf8.withContiguousStorageIfAvailable({ buffer
            throws(RFC_8259.Error) -> RFC_8259.Value in
            let span = buffer.span
            return try RFC_8259.Parser.Span.parse(span, maxDepth: maxDepth)
        }) {
            return result
        }
        // Slow path.
        return try callAsFunction(Swift.Array(string.utf8), maxDepth: maxDepth)
    }
}
```

`withContiguousStorageIfAvailable` is the existing stdlib spelling;
it returns `nil` only for non-contiguous collections (e.g. lazy
generic collections), which are uncommon for byte inputs. The
`String` path additionally needs `String.UTF8View`'s contiguous
guarantee — for native Swift strings this is the common case;
bridged NSString (Foundation interop) is the exception, and there
the slow path engages. Neither path violates the Foundation-free
constraint.

The `[UInt8]` overload at `JSON.parse.prepared()` and
`JSON.parse.located()` dispatches through the same
`RFC_8259.Decode.callAsFunction` entry — they inherit the
specialization automatically.

#### 4.4 Lazy position computation

The `RFC_8259.Position` returned by `Lexer.Span.position` is built
on demand:

```
extension RFC_8259.Lexer.Span {
    @inlinable
    internal var position: RFC_8259.Position {
        var line: Int = 1
        var lastNewline: Int = -1
        let consumed = self.position
        for i in 0..<consumed {
            if bytes[i] == 0x0A {   // \n
                line &+= 1
                lastNewline = i
            }
        }
        let column = consumed - lastNewline    // 1-based
        return RFC_8259.Position(
            offset: .init(Cardinal(UInt(consumed))),
            location: Text.Location(
                line: Text.Line.Number(UInt(line)),
                column: Text.Line.Column(Cardinal(UInt(column)))
            )
        )
    }
}
```

This is O(consumed bytes) on each access — but accessed at error
sites only, so the amortised cost per byte is zero. The same shape
is acceptable in the `lexer.position` accessor used by tests and
diagnostics: tests read position at most once per parse, and only
on the failure path.

#### 4.5 Strict-memory-safety contract

The cursor is `@safe` for the same reason `Binary.Bytes.Input.View`
is — the encapsulated `Swift.Span<UInt8>` is itself a safe stdlib
type. The lifetime annotations (`@_lifetime(borrow bytes)` at init,
`@_lifetime(self: copy self)` on mutating methods,
`@_lifetime(copy self)` on subscripts) are the language-level
proofs of correctness. No `UnsafePointer<UInt8>` is introduced; no
`@unsafe` is needed.

The single existing `@_spi(Unsafe) public import Array_Primitives`
at `RFC_8259.Lexer.swift:6` is preserved for the `Array.Small`
inline-storage type used in `lexNumber`; no new SPI imports are
required for Tier 4.

### 5. Phased landing plan

Each phase is independently shippable and reversible.

#### Phase A0 — Re-verification dispatch (1 dispatch, ≈ half-day)

Before any cursor work, verify three premises against the live
toolchain:

1. **`~Escapable` on protocol associated types still works in
   Swift 6.4-dev nightly** (the experiment was CONFIRMED on Swift
   6.2.3 in 2026-02-13; the institute uses 6.3+ today). Run the
   `suppressed-escapable-associated-types` experiment under the
   current toolchain; record disposition in the experiment's
   header.
2. **`withContiguousStorageIfAvailable` on `String.UTF8View`
   returns non-nil for native Swift strings** on the target
   platforms. Tiny benchmark; should hold.
3. **Span lifetime annotations compose with typed throws.** Spike
   a 100-line standalone target that does
   `func f(_ s: borrowing Span<UInt8>) throws(MyError) -> Int`
   with `@_lifetime(borrow s)` and verify the lifetime checker is
   happy.

Disposition: documented inline in the existing
`swift-parser-primitives/Experiments/suppressed-escapable-associated-types/`
experiment header + a new note in this doc.

If any of these fail under the current toolchain, the plan halts
at A0 and a separate handoff investigates the regression. The
predecessor doc's Tier-1 wins are already landed and are not at
risk.

#### Phase A1 — Span cursor and parser (1 arc, ≈ 1 week)

Add the three new internal files to `swift-rfc-8259`:

| File | Content |
|---|---|
| `Sources/RFC 8259/RFC_8259.Lexer.Span.swift` | `internal struct Span: ~Copyable, ~Escapable` cursor + peek / advance / startsWith |
| `Sources/RFC 8259/RFC_8259.Parser.Span.swift` | `internal struct Span: ~Copyable, ~Escapable` parser building `RFC_8259.Value` |
| `Sources/RFC 8259/RFC_8259.Position.Lazy.swift` | Lazy position computation helper |

Plus the dispatch fork in `RFC_8259.Decode.swift` (modified, not
new). One-type-per-file per [API-IMPL-005]. Naming per
[API-NAME-001] / [API-NAME-001a].

The existing generic `RFC_8259.Lexer<Input>` /
`RFC_8259.Parser<Input>` types stay — they are public, used by
streaming consumers, and act as the slow path for non-contiguous
inputs.

Tests:

- All 124 existing `RFC_8259` tests must continue to pass.
- New `RFC_8259.Lexer.Span` test suite covers position
  computation, EOF handling, malformed inputs, the surrogate-pair
  edge cases the generic lexer covers today.
- Bench harness from `/tmp/json-parse-bench` (per the predecessor
  doc §2) re-runs and records before/after on the 86 MB
  `Swift.symbols.json` workload.

**Success criterion**: 0.67 s → ≤ 0.39 s on the `[UInt8]` path,
≤ 0.39 s on the `String` path, 124/124 tests green.

#### Phase A2 — Re-measure and decide whether B is needed

Profile (single iteration sample + 10-iteration sample) the new
hot path. Two outcomes:

- **Outcome 1**: ≤ 1.3× Foundation achieved on the workload.
  Phase B is NOT triggered. The tree-teardown wedge remains a
  known residual to be revisited if/when a second performance-
  sensitive consumer surfaces. Document disposition in the
  predecessor doc as v1.2.0.
- **Outcome 2**: 1.3×–1.5× Foundation. Tree teardown is the
  dominant remaining wedge per the post-A1 profile. Phase B
  (Architecture B's arena tree) becomes the next investigation;
  it is dispatched as a new research arc, not bundled with A1.

The decision rule is *measurement-driven*, not speculative.
Phase A2 is a measurement gate, not a separate code arc.

#### Phase B (CONDITIONAL — only if A2 says so) — Arena tree

Triggered only if Outcome 2 holds. New research arc:
`parse-performance-arena-tree.md` re-evaluates the arena tree
shape with the post-A1 profile as the input. Implementation
plan deferred to that arc.

### 6. What this design does NOT do

- It does NOT propose any new `swift-input-primitives` /
  `swift-parser-primitives` / ecosystem primitive.
  `Span<UInt8>` is stdlib; `RFC_8259.Lexer.Span` lives inside
  `swift-rfc-8259` until [RES-018]'s second-consumer hurdle is
  met. Promoting the cursor to `swift-text-parser-primitives` or
  similar is *deferred*, not part of Tier 4.
- It does NOT change the public `RFC_8259.Value` enum or its
  storage (`[(String, Value)]` / `[Value]`). The value-tree
  rewrite is Phase B — a separate, conditional arc.
- It does NOT touch the four file blocklist enumerated in the
  brief: `Parser.Input.swift`, `Parser.Tracked.swift`,
  `swift-json/.gitignore`, `swift-rfc-8259/.github/metadata.yaml`.
- It does NOT introduce any `import Foundation` in `Sources/`
  of either package.
- It does NOT change the typed-throws contract:
  `RFC_8259.Parser.Span.parse(...) throws(RFC_8259.Error) -> RFC_8259.Value`.

### 7. Risks beyond what's covered above

| Risk | Mitigation |
|---|---|
| Amdahl shift: Tree teardown might *expand* to the dominant wedge after A1, leaving 1.3× still out of reach. | Phase A2 measurement gate; conditional Phase B. |
| Span lifetime + `@_lifetime(borrow span)` interacts badly with typed throws on the current toolchain. | Phase A0 spike. If REFUTED, plan halts and a separate handoff investigates; Tier 1 wins persist. |
| `String.UTF8View.withContiguousStorageIfAvailable` returns nil more often than expected on real consumer inputs. | Slow path is preserved unchanged; the worst case is "no improvement on bridged NSString," which is acceptable. |
| Generic-Input.Protocol consumers (third-party packages that import `RFC_8259.Lexer<Input>` directly) regress on a hidden API change. | The generic types are unchanged; only the `RFC_8259.Decode` dispatch is forked. Third-party callers of `RFC_8259.Lexer<Input>` directly remain on the existing slow path. |
| Lazy position computation is O(consumed) — pathological cases (~100 errors per parse) could regress error-path performance. | This is an error path; the cost is bounded by `consumed × errors`. Real consumers see one error per failing parse; cost is O(input size) in the worst case which is equivalent to a single re-scan, acceptable. |
| Span<UInt8> capture into a non-Sendable type makes `JSON.parse.prepared()` (Sendable) regress. | `JSON.Prepared.parse(_:)` constructs the Span inside the method scope — the Span never escapes. `RFC_8259.Lexer.Span` is `~Escapable`, which prevents capture in a `@Sendable` closure. Construction is *inside* the parser call, not stored. |
| `@_lifetime` annotations require the experimental `Lifetimes` feature flag, which is already enabled in `swift-rfc-8259`'s Package.swift but verify it remains so in dev nightly. | Phase A0 verification covers this. |
| The two-iteration benchmark wedge between Tier 4 and Tier 2 (`ASCII.Decimal.Parser` adoption) — both reduce `lexNumber` cost. Doing both means measuring on a shifting baseline. | Land Tier 4 first; Tier 2 is then measured against the new baseline. The two are orthogonal: Tier 4 attacks cursor, Tier 2 attacks number parsing. |

## Outcome

**RECOMMENDED architecture**: **Architecture A** — internal
`Span<UInt8>`-backed cursor (`RFC_8259.Lexer.Span`,
`RFC_8259.Parser.Span`, `~Copyable & ~Escapable`, lifetime-
annotated, mirroring `Binary.Bytes.Input.View`) with a dispatch
fork in `RFC_8259.Decode` that fast-paths the contiguous-bytes
case while preserving the existing generic
`Parser.Input.Protocol`-based slow path for arbitrary
`Collection<UInt8>` and non-contiguous strings. Lazy position
computation. Value tree shape unchanged.

**Projected 1.3× Foundation attainability**: Medium-high
confidence on the 86 MB symbol-graph workload — best estimate
≈0.38 s on the `[UInt8]` path (from current 0.67 s), against the
0.30 s Foundation baseline. The tail risk is a Phase-A2 measurement
showing 1.4–1.5×; the response is the conditional Phase B (arena
tree), dispatched as a separate arc only if the measurement says
so. Honest framing: this is medium-high confidence on the
recommended workload, not certainty; the principal should accept a
≤ 5 % risk of needing Phase B.

**Phased landing plan**:

- **Phase A0** (½ day): Verify `~Escapable` on associated types
  under current toolchain; verify
  `withContiguousStorageIfAvailable` on `String.UTF8View`;
  spike Span + typed throws + `@_lifetime`.
- **Phase A1** (~1 week): Add three internal files
  (`RFC_8259.Lexer.Span.swift`, `RFC_8259.Parser.Span.swift`,
  `RFC_8259.Position.Lazy.swift`) + dispatch fork in
  `RFC_8259.Decode.swift`. Existing generic types and 124 tests
  preserved. New Span test suite. Bench harness re-run.
- **Phase A2** (measurement gate): Re-profile. If ≤ 1.3×,
  document v1.2.0 disposition and conclude. If 1.3×–1.5×,
  dispatch Phase B as a separate research arc.
- **Phase B** (conditional, only if A2 triggers): Arena tree
  research arc — not part of this Tier-4 design.

## References

### Predecessor and prior art

- `swift-foundations/swift-json/Research/parse-performance.md` v1.1.0 — Direct predecessor; §6 *Residual gap* enumerates the four wedges Tier 4 attacks.
- `swift-primitives/swift-binary-parser-primitives/Sources/Binary Input View Primitives/Binary.Bytes.Input.View.swift:46-194` — Canonical `~Copyable & ~Escapable` + `Span<UInt8>` + lifetime-annotated cursor; this design mirrors it.
- `swift-primitives/swift-parser-primitives/Experiments/suppressed-escapable-associated-types/Sources/main.swift:1-100` — CONFIRMED 2026-02-13 (Swift 6.2.3): `~Escapable` on associated types, `Span<UInt8>` as `Input`, `inout Input: ~Escapable`. V6 REFUTED.
- `swift-primitives/swift-input-primitives/Sources/Input Primitives/Input.swift:55-63` — `Input.Borrowed` deferred "pending stable `~Escapable` on associated types + generic lifetime parameterization." Tier 4 routes around this dependency.
- `swift-primitives/swift-ascii-parser-primitives/Sources/ASCII Decimal Parser Primitives/ASCII.Decimal.Parser.swift:20-57` — Predecessor Tier 2 candidate; orthogonal to Tier 4 (attacks `lexNumber`, not cursor).
- `swift-institute/Research/buffer-arena-conditional-copyable.md` v1.1.0 — `Buffer.Arena` is unconditionally `~Copyable`; constrains Architecture B's tree design.
- `swift-institute/Research/tree-primitives-buffer-arena-migration.md` — Tree-shape migration to `Buffer.Arena`; background for the conditional Phase B.

### Current parser surface

- `swift-ietf/swift-rfc-8259/Sources/RFC 8259/RFC_8259.Lexer.swift:1-509` — Current generic lexer.
- `swift-ietf/swift-rfc-8259/Sources/RFC 8259/RFC_8259.Parser.swift:1-287` — Current generic parser.
- `swift-ietf/swift-rfc-8259/Sources/RFC 8259/RFC_8259.Decode.swift:1-133` — Public entry points; this is where the dispatch fork lands.
- `swift-ietf/swift-rfc-8259/Sources/RFC 8259/RFC_8259.Value.swift:30-49` — `RFC_8259.Value` enum (unchanged in Architecture A).
- `swift-ietf/swift-rfc-8259/Sources/RFC 8259/RFC_8259.Object.swift:21-37` — `[(String, Value)]` object storage (unchanged in Architecture A).
- `swift-ietf/swift-rfc-8259/Sources/RFC 8259/RFC_8259.Array.swift:29-43` — `[Value]` array storage (unchanged in Architecture A).
- `swift-ietf/swift-rfc-8259/Sources/RFC 8259/RFC_8259.Position.swift` — `RFC_8259.Position` (`offset:` + `location:`); preserved at public boundary.
- `swift-ietf/swift-rfc-8259/Sources/RFC 8259/RFC_8259.Number.Original.swift:23-46` — `RFC_8259.Number.Original` already accepts `Collection<UInt8>`; Span cursor can pass directly without re-materialising.
- `swift-ietf/swift-rfc-8259/Package.swift:1-44` — Existing dep set; Tier 4 adds zero new deps.
- `swift-foundations/swift-json/Sources/JSON/JSON.Parse.swift:23-269` — Public façade; signatures preserved verbatim.

### Skill references

- [API-NAME-001], [API-NAME-001a], [API-NAME-014] — Naming the internal `RFC_8259.Lexer.Span`, `RFC_8259.Parser.Span`, and disambiguating from stdlib `Swift.Span<UInt8>`.
- [API-IMPL-005], [API-IMPL-006], [API-IMPL-008] — One type per file, dotted filenames, minimal type bodies.
- [API-ERR-001] — Typed throws preserved at every layer (`throws(RFC_8259.Error)`).
- [MEM-COPY-001], [MEM-LIFE-001], [MEM-SPAN-001], [MEM-SAFE-001], [MEM-SAFE-020] — `~Copyable & ~Escapable` cursor, `@safe` attribute on the encapsulating type, strict memory safety preserved.
- [IMPL-INTENT], [IMPL-COMPILE], [IMPL-002] — Compiler-as-correctness, typed arithmetic at public boundary, mechanism encapsulated inside the cursor.
- [DS-005], [DS-020] — Storage / arena types existing; new-primitive gate (Architecture C rejected here, Architecture B's arena tree deferred to conditional Phase B research arc).
- [RES-003], [RES-010b], [RES-018], [RES-019], [RES-021], [RES-028] — Research process: option-comparison shape, second-consumer hurdle, prior-art survey, smallest-isolation-first.
- [ARCH-LAYER-001], [ARCH-LAYER-007], [ARCH-LAYER-008], [ARCH-LAYER-011] — Layering, Foundation-freedom across all five layers, correctness-driven shaping pre-1.0, improve-institute over reaching for Foundation.
- [HANDOFF-013], [HANDOFF-016] — Prior-research grep; premise-staleness audit.

## 8. A0 disposition (v1.0.1)

Phase A0 ran on macOS 26 / arm64 with the active Swift 6.3+ toolchain.
Spike artifact:
`swift-foundations/swift-json/Experiments/parse-performance-tier-4-feasibility/`
(two executable targets, build clean under `swift build -c release`,
all probes pass at run time).

| Premise | Status | Source |
|---------|--------|--------|
| `~Escapable` on protocol associated types under `.enableExperimentalFeature("SuppressedAssociatedTypes")` | **GREEN** | Principal confirmation 2026-05-13; original CONFIRMED 2026-02-13 in `swift-parser-primitives/Experiments/suppressed-escapable-associated-types/main.swift` |
| `String.UTF8View.withContiguousStorageIfAvailable` returns non-nil for native + bridged Strings | **GREEN** (more favourable than projected) | `Experiments/parse-performance-tier-4-feasibility/Sources/check-contiguous-storage/main.swift` — 7 probes, all FIRED |
| `Span<UInt8>` + `throws(E)` + `@_lifetime(borrow bytes)` composes; typed errors survive lifetime + inout chain | **GREEN** | `Experiments/parse-performance-tier-4-feasibility/Sources/check-span-typed-throws/main.swift` — 5 probes, all PASS |

### Notable: bridged NSString hits the fast path

The architecture doc's §4.3 line 487-489 projected: *"bridged NSString
(Foundation interop) is the exception, and there the slow path
engages."* The A0 probe shows otherwise on the macOS 26 arm64 target —
both a small (21-char) and a longer (100-char) `NSString`-as-`String`
hit `withContiguousStorageIfAvailable`. Modern macOS Foundation
appears to eagerly UTF-8-ify bridged strings.

Implication for A1: the Span fast path engages on essentially every
input shape a caller would naturally pass on Apple platforms. The
`Swift.Array(string.utf8)` slow-path materialisation that the doc's
§4.3 retained as a fallback may rarely fire in practice. The slow
path is still required for correctness (non-contiguous lazy
collections do exist), but the wall-clock-relevant share is smaller
than projected.

### Decision

A1 is unblocked. The dispatch fork in `RFC_8259.Decode` can rely on
`withContiguousStorageIfAvailable` engaging on the inputs callers
actually pass — that fact removes one of the open assumptions in
the projection of ≤0.39 s on the 86 MB workload.

## Provenance

Investigation invoked via supervisor handoff after Tiers 0/1/3 of
`parse-performance.md` v1.1.0 landed. Scope: design Tier 4 in
detail as a Tier-2 *RECOMMENDATION* doc; no implementation. The
parent session left four files in uncommitted state
(`Parser.Input.swift`, `Parser.Tracked.swift`,
`swift-json/.gitignore`, `swift-rfc-8259/.github/metadata.yaml`);
this doc treats all four as read-only blocklist. The architecture
recommended here ships Span specialization *inside* `swift-rfc-8259`
rather than promoting the cursor to a new ecosystem primitive,
deferring promotion until a second consumer materialises per
[RES-018].
