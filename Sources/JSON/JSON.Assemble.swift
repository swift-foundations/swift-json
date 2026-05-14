/// JSON.Assemble.swift
/// swift-json
///
/// Thin wrapper that adapts `RFC_8259.Span.Assemble.from(_:)` to the
/// `JSON.Error` / `JSON` types expected at the
/// `JSON.Serializable.deserialize(events:)` default-fallback call
/// site (`JSON.Serializable.swift:99`).
///
/// Re-homed from the original `JSON.Assemble` implementation to
/// `RFC_8259.Span.Assemble` per the streaming-deserialize placement
/// audit's Ticket T-2
/// (`swift-institute/Audits/streaming-deserialize-placement-audit.md`):
/// both input (events) and output (`RFC_8259.Value`) are RFC-8259-
/// domain, so the assembler lives in swift-rfc-8259. swift-json
/// retains this ~15-LoC wrapper to preserve the call-site contract
/// without leaking the RFC-8259 types into the JSON deserialize
/// chain.

import RFC_8259

extension JSON {
    /// Helper namespace adapting `RFC_8259.Span.Assemble` to the
    /// `JSON` / `JSON.Error` vocabulary expected by
    /// `JSON.Serializable.deserialize(events:)`.
    @usableFromInline
    internal enum Assemble {}
}

extension JSON.Assemble {
    /// Assembles a `JSON` value by delegating to
    /// `RFC_8259.Span.Assemble.from(_:)` and adapting types.
    ///
    /// FAST PATH and SLOW PATH semantics, including the §4.3 binding
    /// short-circuit at position 0, are owned by
    /// `RFC_8259.Span.Assemble.from(_:)` — see its doc comment for the
    /// canonical description.
    @inlinable
    internal static func from(_ events: inout JSON.Span.EventStream) throws(JSON.Error) -> JSON {
        do throws(RFC_8259.Error) {
            let value = try Lexer.Pull.Assemble.from(&events.inner, strategy: RFC_8259.Pull.Assemble.self)
            return JSON(value)
        } catch {
            throw JSON.Error(error)
        }
    }
}
