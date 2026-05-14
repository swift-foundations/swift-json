# Family-Codable Convention

<!--
---
version: 1.0.0
last_updated: 2026-05-14
status: RECOMMENDATION
tier: 2
scope: cross-package
---
-->

## Context

Between 2026-05-13 and 2026-05-14, a focused review of `swift-foundations/swift-json`'s Codable surface converged on a load-bearing pattern across five packages: `swift-coder-primitives`, `swift-serializer-primitives`, `swift-parser-primitives`, `swift-ascii-parser-primitives` / `swift-ascii-serializer-primitives`, and `swift-foundations/swift-json` itself. The convergent design — the *family-Codable convention* — was reached empirically across waves W1–W5 (serializer-primitives buildout), T1–T2 (typed-throws and streaming integration), and J1 (JSON.Coder + Codable attachment + in-source documentation pass).

The triggering question was: *"should `JSON.Serializable` be phased out in favor of the canonical `Coder_Primitives.Codable`?"* The answer arrived through three iterations:

1. **Initial framing**: rename `JSON.Serializable` → `JSON.Codable` as a refinement of `Coder_Primitives.Codable`.
2. **Counter-framing**: refinement locks stdlib types into a single canonical Codable, contradicting the framing memo's "one Coder per format × value pair." A sibling-protocol pattern is needed.
3. **Convergent**: `JSON.Serializable` stays as-is by name; it IS the JSON sibling of the format-Codable family. Siblings (not refinements) of `Coder_Primitives.Codable`. The canonical attachment is reserved for types-with-one-inherent-canonical-codec (e.g., `RFC_8259.Value`), while format-specific siblings handle the per-format dimension for types whose codec is format-dependent (`Int`, `String`, `Optional`, etc.).

The pattern is documented in source-comment form at `swift-foundations/swift-json/Sources/JSON/JSON.Serializable.swift:1–42` (J1d, commit `0307edc`), and in the user-memory entry `project_parser_serializer_coder_system_framing.md`. This document formalizes the convention beyond the JSON-local source comments, establishes the structural argument, and honestly documents a parser-side tension that remains live.

## Question

How should the ecosystem express "this type is codable in format F" across multiple unrelated formats (JSON, Binary, MessagePack, XML, URL-form-encoded, ...) when stdlib and user-defined types have no single inherent canonical codec, while spec-value types (`RFC_8259.Value`, `RFC_3986.URI`) DO have one?

Sub-questions:

1. What is the formal family-Codable convention, including naming-symmetry between top-level attachment protocols and nested operational protocols?
2. Why siblings, not refinements?
3. How do format-specific siblings compose with the canonical leaf?
4. When does canonical `Codable` apply vs format-specific siblings?
5. How is the parser-side refinement-vs-siblings tension (already shipping in `swift-ascii-parser-primitives`) reconciled with the convergent framing?

## Analysis

### 1. The convention

The family-Codable convention has three structural elements: **canonical attachment protocols** (top-level), **operational protocols** (nested), and **format-specific sibling attachment protocols** (top-level, namespaced to the format).

#### Canonical attachment protocols (top-level of their packages)

These declare a type's *single inherent canonical codec/parser/serializer*. They are top-level in their packages and named in the noun form (`Codable`, `Parseable`, `Serializable`) — they shadow `Swift.Codable` etc. by design.

| Protocol | Declares | File:line |
|----------|----------|-----------|
| `Coder_Primitives.Codable` | A type that has one canonical bidirectional `Coder` | `swift-primitives/swift-coder-primitives/Sources/Coder Primitives/Codable.swift:26–32` |
| `Parser_Primitives_Core.Parseable` | A type that has one canonical `Parser` | `swift-primitives/swift-parser-primitives/Sources/Parser Primitives Core/Parseable.swift:19–25` |
| `Serializer_Primitives_Core.Serializable` | A type that has one canonical `Serializer` | `swift-primitives/swift-serializer-primitives/Sources/Serializer Primitives Core/Serializable.swift:19–25` |

Each carries a single `associatedtype` (`Coder` / `Parser` / `Serializer`) refining the operational `.Protocol` nested type, and a single static accessor (`.coder` / `.parser` / `.serializer`).

#### Operational protocols (nested under their namespaces)

These describe the *verb*: what it means to be a coder/parser/serializer. They are nested under their namespace (`Coder`, `Parser`, `Serializer`) with the `Protocol` member name, e.g., `Coder.Protocol`.

| Protocol | Verb | Reference |
|----------|------|-----------|
| `Coder_Primitives.Coder.Protocol` | A leaf bidirectional codec; one per format × value | Used as `associatedtype Coder: Coder_Primitives.Coder.Protocol` in `Codable.swift:28` |
| `Parser_Primitives_Core.Parser.Protocol` | A parser combinator / leaf parser | Used as `associatedtype Parser: Parser_Primitives_Core.Parser.Protocol` in `Parseable.swift:21` |
| `Serializer_Primitives_Core.Serializer.Protocol` | A serializer combinator / leaf serializer | Used as `associatedtype Serializer: Serializer_Primitives_Core.Serializer.Protocol` in `Serializable.swift:21` |

#### Format-specific sibling attachment protocols (top-level, namespaced)

For each format `F`, a sibling protocol `F.Codable` / `F.Serializable` / `F.Parseable` lives top-level (or top-level within the format's namespace), at the same conceptual rank as the canonical protocol — NOT as a refinement.

Concrete instance (J1d, 2026-05-14): `JSON.Serializable`, declared at `swift-foundations/swift-json/Sources/JSON/JSON.Serializable.swift:94–129`. The protocol declares per-type `serialize` / `deserialize` requirements PLUS an event-grain `deserialize(events:)` requirement (introduced in commit `64a0ce2`, Wave 0c). It is *not* declared as `JSON.Serializable: Coder_Primitives.Codable`.

### 2. The structural argument: why siblings, not refinements

Swift's `associatedtype` semantics impose a categorical constraint: a type can have only ONE conformance of a given protocol per program. A `Codable` conformance commits to ONE `associatedtype Coder` value. Refining `Codable` into `JSON.Codable: Coder_Primitives.Codable` therefore forces the following:

> If `Int: JSON.Codable`, then `Int: Coder_Primitives.Codable` — and `Int.Coder` is whatever `JSON.Codable` picks. Subsequent attempts to write `Int: Binary.LittleEndian.Codable` (a sibling refinement) would either redundantly pick the same Coder (collision) or pick a different one (Swift forbids: `Int` already conforms to `Coder_Primitives.Codable` with the JSON-flavored Coder).

This contradicts the framing memo's foundational tenet: *one `Coder` per `(format, value)` pair*. Stdlib types and user-defined types have NO inherent canonical codec — `Int` is JSON-numeric, ASCII-decimal, big-endian-binary, little-endian-binary, MessagePack-int-family, etc., simultaneously. Refinement forces a global commitment that the type's nature does not support.

**Siblings** sidestep this by living at the same conceptual rank as `Codable`: `Int: JSON.Serializable` and `Int: Binary.LittleEndian.Codable` (future) and `Int: MessagePack.Codable` (future) all coexist freely because they are independent protocols, each with its OWN `associatedtype` slot. The ecosystem-wide canonical `Coder_Primitives.Codable` remains *unconformed* by `Int`, accurately reflecting that `Int` has no single inherent canonical codec.

The empirical structure already on disk validates this: `JSON.Serializable` is the JSON sibling; `Int: JSON.Serializable` (`JSON.Serializable.swift:357–385`) coexists with future `Int: Binary.LittleEndian.Codable` slots without conflict.

### 3. Composition rule: format-specific siblings compose through the canonical leaf

A format-specific sibling does NOT carry a parallel grammar. It is the *ergonomic surface* over the same canonical leaf.

Concrete trace:

| Call site | Routes through |
|-----------|----------------|
| `JSON.Coder.decode(_:)` | `JSON.Decode.Implementation.parse` — `JSON.Coder.swift:86` |
| `JSON.Serializable.init(jsonBytes:)` | `JSON.parse(jsonBytes)` → `JSON.Decode.Implementation.parse` — `JSON.Serializable.swift:189–193`, `JSON.Parse.swift:51,67,188,204` |
| `RFC_8259.Value(decoding: &input)` | `JSON.Coder.decode(_:)` (via `Codable` extension default) — `Codable.swift:51–54` |

All three converge on `JSON.Decode.Implementation.parse`. The sibling protocol is NOT a re-implementation of JSON parsing; it is a JSON-specific public surface (per-type `serialize`/`deserialize`, event-grain fast path, format-aware Optional null-sentinel semantics — see `JSON.Serializable.swift:556–585`) over the canonical leaf.

The event-grain `deserialize(events:)` requirement (Wave 0c, commit `64a0ce2`) is the empirical fastpath case: types that override the default implementation skip full-tree materialisation, but the underlying lexer (`RFC_8259.Span.Lexer`, see `parse-performance-architecture.md`) is the same one the canonical `Coder.decode` uses. The composition through-the-leaf is structural, not coincidental.

### 4. When canonical Codable applies vs format-specific siblings

| Type class | Canonical `Codable` | Format-specific sibling |
|-----------|---------------------|-------------------------|
| Spec-value types (`RFC_8259.Value`, `RFC_3986.URI`, `RFC_4122.UUID` future) — ONE inherent canonical codec | **YES** — attach the canonical Coder | Optional — same type MAY also conform to a sibling if it has an ergonomic JSON-specific surface |
| Stdlib types (`Int`, `String`, `Optional`, `Array`, `Dictionary`) — NO inherent canonical codec | **NO** — refusing the canonical conformance is the correct stance | **YES** — conform to per-format siblings (`Int: JSON.Serializable`, future `Int: Binary.LittleEndian.Codable`) |
| User-defined value types (`User`, `Product`, ...) — NO inherent canonical codec | **NO** — same reasoning as stdlib types | **YES** — conform to per-format siblings; the user chooses which formats their type supports |

Concrete empirical examples:

- `RFC_8259.Value: @retroactive Coder_Primitives.Codable` with `typealias Coder = JSON.Coder` — `JSON.Coder.swift:110–116`. This is the canonical attachment for the *only* type whose inherent codec is unambiguously JSON.
- `JSON: JSON.Serializable` — `JSON.Serializable.swift:281–299`. `JSON` (the swift-json public façade) carries the sibling conformance because the sibling protocol IS the JSON-ergonomic surface; it does not also need the canonical attachment.
- `Int: JSON.Serializable` — `JSON.Serializable.swift:357–385`. Stdlib type conforms to the sibling but NOT to `Coder_Primitives.Codable`.
- `Optional: JSON.Serializable where Wrapped: JSON.Serializable` — `JSON.Serializable.swift:556–585`. Wraps with format-natural null-sentinel semantics (nil → JSON null literal).

A type MAY have both canonical and sibling conformances pointing to the same underlying leaf (this is `RFC_8259.Value`'s case in principle — it conforms to canonical `Codable` via `JSON.Coder`, and if it conformed additionally to `JSON.Serializable` the two would compose through the same `JSON.Decode.Implementation.parse` leaf). There is no conflict because the protocols are independent.

### 5. Naming-symmetry rule

The canonical naming-symmetry is:

| Rank | Position | Names |
|------|----------|-------|
| Top-level (canonical attachment) | Top-level of the primitives package | `Codable`, `Parseable`, `Serializable` |
| Top-level (format-specific sibling) | Top-level within the format's namespace | `JSON.Serializable`, future `Binary.LittleEndian.Codable`, future `MessagePack.Codable`, future `XML.Codable`, future `URL.FormEncoded.Codable` |
| Nested (operational) | `Coder.Protocol`, `Parser.Protocol`, `Serializer.Protocol` | Inside the corresponding namespace |

The reason for the top-level placement of the attachment protocols (canonical and siblings alike) is that *attachment is metadata about a type* — "this type is codable in this way." Operational protocols (`Coder.Protocol`, etc.) are the *verb* — "this type performs the coding." Keeping metadata at the top level distinct from the operation namespace prevents the noun and the verb from colliding in namespace, and lets conformance lists read as `extension T: JSON.Serializable` (metadata-style) while operational dispatch reads as `T.serializer.serialize(...)` (verb-style).

This is mechanically reflected in the existing surface:

- `extension RFC_8259.Value: @retroactive Coder_Primitives.Codable { typealias Coder = JSON.Coder; ... }` (`JSON.Coder.swift:110–116`) — top-level `Codable`, nested `Coder` typealias pointing at the leaf.
- `extension IPv4.Address: Serializable { static var serializer: IPv4.Address.Serializer { .init() } }` (example from `Serializable.swift:13–18` docstring) — top-level `Serializable`, nested operational `Serializer` type.

### 6. The parser-side refinement-vs-siblings tension

The convergent framing argues for **siblings, not refinements**. The serializer/coder side empirically follows this:

- `Optional: Serializable where Wrapped: Serializable` (`Optional+Serializable.swift:21–25`, commit `3f4f897` / Wave W5b) conforms to the **canonical** top-level `Serializer_Primitives_Core.Serializable`, NOT to a `JSON.Serializable` or `ASCII.Serializable` sibling. This is reasonable because *that particular serializer* (`Serializer.Optionally<Wrapped.Serializer>`) is intrinsically format-agnostic — its semantics (no-bytes-emitted for nil) are the canonical "absent value" semantics across many binary formats.
- `Int: @retroactive Serializable { static var serializer: ASCII.Decimal.Serializer<Int> { .init() } }` (`FixedWidthInteger+Serializable.swift:8–10`) ALSO conforms to the canonical `Serializable` directly, pinning `Int.serializer` to the ASCII decimal serializer.

**However**, the parser side has a structurally different shape — and this is the live tension:

`ASCII.Parseable` IS declared as a **refinement**:

```swift
// swift-primitives/swift-ascii-parser-primitives/Sources/ASCII Parser Primitives Core/ASCII.Parseable.swift:10–18
extension ASCII {
    public protocol Parseable: Parser_Primitives_Core.Parseable {}
}
```

And the stdlib integer conformances carry BOTH:

```swift
// swift-primitives/swift-ascii-parser-primitives/Sources/ASCII Parser Primitives Standard Library Integration/FixedWidthInteger+Parseable.swift:11–13
extension Int: ASCII.Parseable, @retroactive Parseable {
    public static var parser: ASCII.Decimal.Parser<Parser.Input.Bytes, Int> { .init() }
}
```

The structural consequence: `Int` is committed at the canonical `Parser_Primitives_Core.Parseable` level to the ASCII decimal parser. A future `Binary.LittleEndian.Parseable: Parser_Primitives_Core.Parseable` (refinement) would NOT be able to add `Int: Binary.LittleEndian.Parseable` without either (a) committing `Int.parser` to the LE-binary parser (conflict with the existing ASCII-decimal commitment) or (b) making `Binary.LittleEndian.Parseable` a non-refining sibling, which contradicts the parser-side's current shape.

The serializer side hit and resolved an analogous issue differently:
- `Int: @retroactive Serializable` (`FixedWidthInteger+Serializable.swift:8–10`) pins `Int.serializer` to ASCII decimal — same shape as the parser side.
- But the previous attempt at a sibling refinement protocol — `Binary.ASCII.Serializable` — has been **deprecated** as of W4 (commit `b9abbff`, "Remove legacy Serialization namespace"). The deprecation message at `Binary.ASCII.Serializable.swift:7` reads: *"Use `Binary.Serializable` / `Parser.Protocol` conformances directly; legacy Serialization namespace was removed in W4."* The protocol IS retained but no longer the recommended path.

The serializer-side state, then, is *transitional*: legacy `Binary.ASCII.Serializable: Binary.Serializable` (refinement-shape) deprecated; new conformances go directly on `Serializable`. But `JSON.Serializable` (introduced J1, pre-existing) is shaped as a non-refining sibling — the structurally correct shape under the convergent framing.

#### Why this tension is real and not papered over

The tension is empirically live across two surfaces:

1. **`Int.parser` is committed ecosystem-wide to ASCII decimal**. There is no current second-format parser conformance to test the lockout hypothesis against. The parser side is *consistent* today only because there is exactly one format-Parseable in production (ASCII). The structural defect is latent, not yet observable in build failures.
2. **`Int.serializer` is committed ecosystem-wide to ASCII decimal** via the canonical `Serializable`, not via a refining sibling. This commits the same global lockout — but at the canonical level, not at a sibling level. Future `Binary.LittleEndian.Serializable: Serializer_Primitives_Core.Serializable` (as a refinement) would face exactly the same conflict. The W4 deprecation of `Binary.ASCII.Serializable` signals an intent to retreat from sibling-as-refinement, but the alternative — siblings-as-non-refinements — is not yet expressed in primitives-level shape. Only `JSON.Serializable` (a foundations-level type) demonstrates the non-refining sibling shape.

The convergent framing's outcomes against this tension are three:

(a) **Parser side is consistent and the "siblings" framing is wrong** — REJECTED. The framing memo's "one Coder per (format, value)" tenet is foundational; a single canonical commitment that allows only one format-parser ecosystem-wide is the structural defect the framing was designed to avoid.

(b) **Parser side is inconsistent with the framing and should be migrated to siblings too in a future arc** — RECOMMENDED. The migration would (i) remove `ASCII.Parseable: Parser_Primitives_Core.Parseable` and re-declare `ASCII.Parseable` as a non-refining sibling top-level under `ASCII`, (ii) drop the `@retroactive Parseable` conformance on stdlib integers and retain only `ASCII.Parseable` (and any other format-specific sibling), and (iii) recover the freedom to add `Binary.LittleEndian.Parseable` (a sibling) with `Int: Binary.LittleEndian.Parseable` coexisting with `Int: ASCII.Parseable`. The same migration applies to the canonical `Serializable` conformance on stdlib integers — drop the canonical, retain format-specific siblings.

(c) **The parser side's refinement is structurally tolerated because there's only one ASCII parser** — TEMPORARILY ACCEPTED. The lockout defect cannot fire until a second format-Parseable is proposed. The structural fix (option b) is queued; the urgency depends on when a second format-Parseable arrives. **This is the current state**: the convention as documented in this Research doc takes (b) as the principled position, but the migration is not in flight at the time of writing. The tension is filed as a known structural inconsistency awaiting the trigger.

**Outcome of this section**: the family-Codable convention is **siblings, not refinements**, structurally. The parser side currently violates this (refinement-shaped). The serializer side has retreated from refining siblings (deprecation of `Binary.ASCII.Serializable`) but stdlib integer conformances are still on canonical `Serializable`, pinning them to ASCII. The convergent framing is the **target state**; the empirical state is mixed. Migrating parser-side and stdlib serializer conformances to non-refining siblings is a queued arc, not a pre-1.0 blocker for swift-json itself (whose `JSON.Serializable` already follows the convention).

### 7. Future sibling protocols

Anticipated future siblings (not prescribed — slots reserved):

| Format | Sibling protocol (anticipated) | Likely Coder leaf |
|--------|-------------------------------|-------------------|
| Big-endian binary | `Binary.BigEndian.Codable` | `Binary.BigEndian.Coder` |
| Little-endian binary | `Binary.LittleEndian.Codable` | `Binary.LittleEndian.Coder` |
| MessagePack | `MessagePack.Codable` | `MessagePack.Coder` |
| XML (specific dialect) | `XML.Codable` | `XML.Coder` per dialect |
| URL form-encoded | `URL.FormEncoded.Codable` | `URL.FormEncoded.Coder` |
| ASCII (already in parsing) | `ASCII.Codable` (if a coder unifies parser + serializer for ASCII) | `ASCII.Decimal.Coder` per cell |

Each follows the pattern:

1. Own namespace at the format's top level.
2. Top-level sibling attachment protocol (`F.Codable`, `F.Serializable`, or `F.Parseable`) declaring per-type requirements (`serialize`/`deserialize`, `parse`, or both).
3. Per-type conformances at the format's package level (`extension Int: F.Codable`, etc.).
4. Composition through the format's canonical leaf coder/parser/serializer.

When the second non-trivial format-Codable lands, this Research doc SHOULD be promoted to `swift-institute/Research/` for ecosystem-level reference per `[RES-002a]`'s "multiple packages, no clear owner, or spanning layers" criterion.

### 8. Per-format Optional semantics

Wave W5b adopted `Optional<T>: Serializable where Wrapped: Serializable` with `Serializer.Optionally` semantics (`Optional+Serializable.swift:21–25`):

```swift
extension Swift.Optional: Serializable where Wrapped: Serializable {
    public static var serializer: Serializer_Primitives_Core.Serializer.Optionally<Wrapped.Serializer> {
        Serializer_Primitives_Core.Serializer.Optionally(Wrapped.serializer)
    }
}
```

Semantics: nil → no bytes emitted; `.some(value)` → delegate to wrapped serializer. This is the natural "absent value" semantics for length-prefixed and tag-based binary formats.

In parallel, `Optional<T>: JSON.Serializable where Wrapped: JSON.Serializable` adopts null-sentinel semantics (`JSON.Serializable.swift:556–585`):

```swift
extension Optional: JSON.Serializable where Wrapped: JSON.Serializable {
    public static func serialize(_ value: Wrapped?) -> JSON {
        guard let value else { return .null }
        return value.json
    }
    // deserialize: 'n' → .null token → nil; else delegate to Wrapped
}
```

Semantics: nil → JSON `null` literal; `.some(value)` → delegate to wrapped serialization.

The two conformances are **parallel, not conflicting**, because they are on sibling protocols (`Serializer_Primitives_Core.Serializable` vs `JSON.Serializable`). Each format-Codable's Optional conformance encodes the **format's natural null representation**:

| Format | Optional nil encoding |
|--------|----------------------|
| Binary (`Serializer.Optionally`) | No bytes — assumes outer framing carries optionality |
| JSON (`JSON.Serializable`) | `null` literal — JSON has an explicit null grammar |
| MessagePack (future) | `0xC0` byte — MessagePack has an explicit nil tag |
| XML (future) | Element absence OR `xsi:nil="true"` — context-dependent |

This is structurally the strongest empirical validation of the sibling-not-refinement convention to date: the same `Optional<Wrapped>` carries TWO non-conflicting conformances, each pinning a format-natural serializer, and they coexist exactly because the sibling protocols do not refine each other.

## Comparison

The two structural options were exhausted across the three iterations recorded in Context:

| Criterion | Refinement (`JSON.Codable: Coder_Primitives.Codable`) | Sibling (`JSON.Serializable` independent) |
|-----------|------------------------------------------------------|-------------------------------------------|
| Stdlib type freedom | LOCKED — one canonical codec per type ecosystem-wide | FREE — parallel sibling conformances coexist |
| Reflection of "one Coder per (format, value)" tenet | VIOLATES — collapses formats at the canonical level | RESPECTS — each format has its own slot |
| Composition through canonical leaf | YES (trivially, by inheritance) | YES (explicitly, by routing through the format's Coder) |
| Naming clarity | "Codable" with format qualifier reads as variant of canonical | "Serializable" / "Codable" at format namespace reads as orthogonal capability |
| Empirical W4 retreat from `Binary.ASCII.Serializable` (refinement shape) | Suggests refinement-shape was found defective in practice | Supports the migration path |
| Future-extensibility (Binary.LE / MessagePack / XML / URL-form) | BLOCKED on stdlib types if any prior format claimed `Int.coder` | UNBLOCKED — each sibling owns its slot |

## Outcome

**Status**: RECOMMENDATION

**Conclusion**: The family-Codable convention — *siblings, not refinements; top-level naming-symmetry; composition through the canonical leaf* — is the institute's structural answer to multi-format coding/parsing/serialization across types with no single inherent canonical codec. The convention is:

1. **Canonical attachment protocols** (`Coder_Primitives.Codable`, `Parser_Primitives_Core.Parseable`, `Serializer_Primitives_Core.Serializable`) live top-level in their packages, name-aligned with their value class, and are conformed ONLY by types with one inherent canonical codec (spec-value types like `RFC_8259.Value`).
2. **Operational protocols** (`Coder.Protocol`, `Parser.Protocol`, `Serializer.Protocol`) live nested under their namespaces and describe the *verb*.
3. **Format-specific sibling attachment protocols** (`JSON.Serializable`, future `Binary.LittleEndian.Codable`, etc.) live top-level within the format's namespace, are NON-refining (independent of the canonical attachment protocols), and carry per-type conformances for stdlib and user-defined types whose codec is format-specific.
4. **Composition** happens through the canonical leaf coder/parser/serializer — sibling protocols are ergonomic surfaces, not parallel grammars.
5. **Optional semantics** are format-natural per sibling (JSON: null literal; Binary: no-bytes; MessagePack: nil tag; XML: element-absence).

**Implementation state** (CONFIRMED elements / RECOMMENDED migrations):

| Element | Status | Evidence |
|---------|--------|----------|
| `JSON.Serializable` as non-refining sibling | CONFIRMED (in production) | `JSON.Serializable.swift:94`, commit `0307edc` (J1d) |
| `RFC_8259.Value: Coder_Primitives.Codable` with `JSON.Coder` leaf | CONFIRMED (in production) | `JSON.Coder.swift:110–116`, commit `3500d18` (Arc 1.5) |
| `Optional: JSON.Serializable` parallel to `Optional: Serializable` | CONFIRMED (in production) | `JSON.Serializable.swift:556`, `Optional+Serializable.swift:21`, commit `3f4f897` (W5b) |
| `Binary.ASCII.Serializable` refinement-shape | DEPRECATED | `Binary.ASCII.Serializable.swift:7–8`, commit `b9abbff` (W4d) |
| `ASCII.Parseable: Parser_Primitives_Core.Parseable` (refinement) | RECOMMENDED-FOR-MIGRATION | `ASCII.Parseable.swift:10–18`, commit `747c28a` — see §6, option (b) |
| Stdlib integer `@retroactive Parseable` + `@retroactive Serializable` (canonical pinning) | RECOMMENDED-FOR-MIGRATION | `FixedWidthInteger+Parseable.swift:11`, `FixedWidthInteger+Serializable.swift:8` — drop canonical, retain format-specific sibling per §6, option (b) |

**Implementation notes**:

- The convention DOCUMENTS what is now in place across `swift-json` and the post-W4 serializer-primitives state. It does NOT prescribe renaming any existing protocol.
- The parser-side refinement-vs-siblings tension is REAL and queued for resolution. The trigger is the arrival of a second non-trivial format-Parseable; until then, the structural defect is latent.
- A future second format-Codable (e.g., a Binary.LittleEndian.Codable shipping the parallel structure) should trigger promotion of this Research doc to `swift-institute/Research/` per `[RES-002a]`.

## References

- `swift-foundations/swift-json/Sources/JSON/JSON.Serializable.swift` (commit `0307edc`, 2026-05-14, J1d)
- `swift-foundations/swift-json/Sources/JSON/JSON.Coder.swift` (commit `3500d18`, Arc 1.5)
- `swift-primitives/swift-coder-primitives/Sources/Coder Primitives/Codable.swift`
- `swift-primitives/swift-parser-primitives/Sources/Parser Primitives Core/Parseable.swift`
- `swift-primitives/swift-serializer-primitives/Sources/Serializer Primitives Core/Serializable.swift`
- `swift-primitives/swift-ascii-parser-primitives/Sources/ASCII Parser Primitives Core/ASCII.Parseable.swift` (commit `747c28a`)
- `swift-primitives/swift-ascii-parser-primitives/Sources/ASCII Parser Primitives Standard Library Integration/FixedWidthInteger+Parseable.swift` (commit `68e02d7`)
- `swift-primitives/swift-ascii-serializer-primitives/Sources/Binary ASCII Serializable Primitives/Binary.ASCII.Serializable.swift` (deprecation commit `b9abbff` / W4d, message at line 7)
- `swift-primitives/swift-ascii-serializer-primitives/Sources/Serializable Integer Primitives/FixedWidthInteger+Serializable.swift`
- `swift-primitives/swift-serializer-primitives/Sources/Serializer Primitives Standard Library Integration/Optional+Serializable.swift` (commit `3f4f897`, W5b)
- User memory: `project_parser_serializer_coder_system_framing.md` (framing memo locking in sibling-not-refinement and naming-symmetry; cited in `JSON.Coder.swift:11–14` as "the swift-coder-primitives framing memo")
- Adjacent: `parse-performance-architecture.md` v1.0.2 (DECISION) — RFC_8259.Span.Lexer naming refinement underpinning the canonical leaf
