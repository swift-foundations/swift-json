# Audit: swift-json

## Legacy — Consolidated 2026-04-08

### From: swift-institute/Research/modularization-audit-foundations-single-target.md (2026-03-20)

**Modularization audit — single-target packages**

#### MOD-010: StdLib Extension Isolation — 4 files

| File | Extends | API Added |
|------|---------|-----------|
| `Bool+JSON.swift` | `Bool` | `init?(_ json: JSON)` |
| `Int+JSON.swift` | `Int` | `init?(_ json: JSON)` |
| `Double+JSON.swift` | `Double` | `init?(_ json: JSON)` |
| `String+JSON.swift` | `String` | `init?(_ json: JSON)` |

Additionally, `JSON.Serializable.swift` extends `Optional`, `Array`, `Dictionary`, `Int`, `Double`, `Bool`, `String` with `JSON.Serializable` conformances.

These are domain-coupled (they require `JSON` types in their signatures) so isolating them into a separate StdLib Integration module is reasonable but not urgent. They add public API surface to stdlib types in every consumer's namespace.

**Action**: Consider a `JSON StdLib Integration` module to let consumers opt in.

#### MOD-011: No Test Support Product

| Files | External Deps | Has Test Support |
|------:|:-------------:|:----------------:|
| 11 | 3 | N |

Package meets the criteria for a test support product (10+ files, 3+ external deps) but does not provide one. Most likely candidate among the single-target packages — downstream packages testing JSON serialization would benefit from test fixtures and assertion helpers.
