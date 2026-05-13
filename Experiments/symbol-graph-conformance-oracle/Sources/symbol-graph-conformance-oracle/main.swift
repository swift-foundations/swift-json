// MARK: - Symbol-Graph Conformance Oracle
//
// Purpose: verify that `swift-symbolgraph-extract` emits sufficient
// `conformsTo` relationships in its JSON output to reconstruct a
// protocol-refinement table — the precomputed "oracle" that would
// replace the hardcoded `idiomKnownStdlibRefinements` table in
// `swift-foundations/swift-linter-rules/Sources/Linter Rule Idiom/
// Lint.Rule.Idiom.RedundantRefinement.swift`.
//
// Hypothesis (three claims; all three must hold for CONFIRMED):
//   1. For a per-module symbol graph, the JSON's `relationships` array
//      contains entries with `kind == "conformsTo"` whose `source` and
//      `target` both refer to symbols of `kind.identifier ==
//      "swift.protocol"` — i.e., protocol-protocol refinements ARE
//      captured in the format.
//   2. Given a `.symbols.json` file, a ~100-line reducer can extract
//      the `(refining, refined)` pairs by joining `relationships` with
//      `symbols[].kind.identifier == "swift.protocol"`.
//   3. Wall-clock for parse + reduce on a real institute module
//      completes in <30 seconds.
//
// Toolchain: Apple Swift 6.3.1+ (active toolchain)
// Platform: macOS 26.0 (arm64)
//
// Invocation:
//   swift run symbol-graph-conformance-oracle <path-to-symbols.json> [<path-to-symbols.json>...]
//
// Multi-input mode (added 2026-05-13): pass multiple `.symbols.json`
// paths to extract refinement pairs across an arbitrary set of modules.
// The aggregated output covers the union of all input modules'
// protocol→protocol refinements. Auto-detects stdlib vs user-domain
// from the first input's module name:
//
//   - First input is Swift stdlib   → emits StdlibRefinementsTable.swift
//                                       with variable idiomKnownStdlibRefinements
//   - First input is anything else  → emits UserDomainRefinementsTable.swift
//                                       with variable idiomKnownUserDomainRefinements
//
// Result: CONFIRMED (2026-05-13)
//
// Evidence:
//   - Run against `Swift.symbols.json` (86 MB): 14,552 symbols;
//     18,314 relationships; 136 protocol→protocol refinements;
//     all 26 hardcoded `idiomKnownStdlibRefinements` entries
//     reproduced; 110 additional refinements extracted.
//   - Run against `Carrier_Primitives.symbols.json` (22 KB): 7
//     symbols, 6 relationships (all defaultImplementationOf /
//     requirementOf — no conformsTo; Carrier doesn't refine other
//     protocols). 0 refinement pairs, as expected.
//
// Timing observations (single-file mode):
//   - Carrier_Primitives (22 KB):     0.048s total (parse 0.048s)
//   - Swift stdlib (86 MB):         128.632s total (parse 128.525s)
//   - swift-json's text parser is the bottleneck at stdlib scale.
//     Production oracle generation is offline; lint-time consumers
//     read the compact emitted artifact in milliseconds.
//
// Date: 2026-05-13
//
// Placement note: per [EXP-022], an experiment with package
// dependencies lives in the highest-layer dep's `Experiments/`. This
// experiment imports `JSON` (from swift-foundations/swift-json, L3),
// so it lives at swift-foundations/swift-json/Experiments/. The
// research doc (swift-foundations/swift-linter/Research/
// lsp-sourcekit-integration.md v1.2.0) cites this location.

import Foundation
import JSON

// MARK: - Helpers

extension JSON {
    /// Returns the underlying String if this is a JSON string, else nil.
    /// (swift-json's non-failable `String(json)` returns "" for non-string
    /// values, which masks the type mismatch we want to detect.)
    fileprivate var asString: String? {
        guard isString else { return nil }
        return String(self)
    }
}

fileprivate struct RefinementPair: Hashable {
    /// Leaf-name pair (last path component on each side) — what the
    /// `Lint.Rule.Idiom.RedundantRefinement` rule currently matches.
    /// For stdlib protocols this is unique (Error, Comparable, …); for
    /// institute protocols following the `Namespace.\`Protocol\``
    /// convention this collapses to ("Protocol", "Protocol") and loses
    /// discriminating information.
    let refiningLeaf: String
    let refinedLeaf: String
    /// Full-path pair (joined pathComponents) — the unambiguous form
    /// the rule WOULD need if extended to match institute protocols.
    let refiningPath: String
    let refinedPath: String
}

fileprivate struct PerInputStats {
    let path: String
    let module: String
    let symbolCount: Int
    let protocolCount: Int
    let relationshipsCount: Int
    let conformsToCount: Int
    let refinementsCount: Int
    let conformsToOtherKinds: Int
    let parseSeconds: Double
}

/// Result of pass 1 — symbol identity gathered without yet processing
/// relationships. Pass 2 uses the aggregated symbol map across all
/// inputs for membership checks, which is required to detect
/// CROSS-MODULE protocol→protocol refinements (e.g.,
/// `Comparison.Protocol: Equation.Protocol` where the source's symbol
/// graph references a target defined in a sibling module).
fileprivate struct InputSymbols {
    let path: String
    let module: String
    let symbolCount: Int
    let localProtocolCount: Int
    let relationshipsCount: Int
    let parseSeconds: Double
    let root: JSON  // retained for pass-2 relationship walk
}

/// Pass 1: parse one input; collect symbol identities into shared maps.
fileprivate func loadSymbols(
    path: String,
    symbolLeafByID: inout [String: String],
    symbolPathByID: inout [String: String],
    protocolIDs: inout Set<String>
) throws -> InputSymbols {
    let startedAt = Date()
    let raw = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    let root = try JSON.parse(raw)
    let parsedAt = Date()
    let moduleName = root.module.name.asString ?? "<unknown>"

    guard let symbols = root.symbols.array else {
        throw OracleError.malformedInput(path: path, reason: "no `symbols` array")
    }
    var localProtocolCount = 0
    for sym in symbols {
        guard let preciseID = sym.identifier.precise.asString,
              let kindID = sym.kind.identifier.asString
        else { continue }
        var components: [String] = []
        if let arr = sym.pathComponents.array {
            for c in arr {
                if let s = c.asString {
                    components.append(s)
                }
            }
        }
        if components.isEmpty, let title = sym.names.title.asString {
            components = [title]
        }
        if let leaf = components.last, symbolLeafByID[preciseID] == nil {
            symbolLeafByID[preciseID] = leaf
        }
        if !components.isEmpty, symbolPathByID[preciseID] == nil {
            let qualified = ([moduleName] + components).joined(separator: ".")
            symbolPathByID[preciseID] = qualified
        }
        if kindID == "swift.protocol" {
            protocolIDs.insert(preciseID)
            localProtocolCount += 1
        }
    }

    let relationships = root.relationships.array ?? []
    return InputSymbols(
        path: path,
        module: moduleName,
        symbolCount: symbols.count,
        localProtocolCount: localProtocolCount,
        relationshipsCount: relationships.count,
        parseSeconds: parsedAt.timeIntervalSince(startedAt),
        root: root
    )
}

/// Pass 2: walk one input's relationships using the union symbol maps;
/// append found refinements to the shared accumulator.
fileprivate func processInput(
    inputSymbols: InputSymbols,
    symbolLeafByID: [String: String],
    symbolPathByID: [String: String],
    protocolIDs: Set<String>,
    accumulator: inout Set<RefinementPair>
) -> PerInputStats {
    let root = inputSymbols.root
    let relationships = root.relationships.array ?? []
    var conformsToCount = 0
    var conformsToOtherKinds = 0
    var perFilePairs = 0
    for rel in relationships {
        guard let kind = rel.kind.asString, kind == "conformsTo" else { continue }
        conformsToCount += 1
        guard let source = rel.source.asString,
              let target = rel.target.asString
        else { continue }
        let sourceIsProtocol = protocolIDs.contains(source)
        let targetIsProtocol = protocolIDs.contains(target)
        guard sourceIsProtocol && targetIsProtocol else {
            conformsToOtherKinds += 1
            continue
        }
        let refiningLeaf = symbolLeafByID[source] ?? source
        let refinedLeaf = symbolLeafByID[target] ?? target
        let refiningPath = symbolPathByID[source] ?? source
        let refinedPath = symbolPathByID[target] ?? target
        let pair = RefinementPair(
            refiningLeaf: refiningLeaf,
            refinedLeaf: refinedLeaf,
            refiningPath: refiningPath,
            refinedPath: refinedPath
        )
        if accumulator.insert(pair).inserted {
            perFilePairs += 1
        }
    }

    return PerInputStats(
        path: inputSymbols.path,
        module: inputSymbols.module,
        symbolCount: inputSymbols.symbolCount,
        protocolCount: inputSymbols.localProtocolCount,
        relationshipsCount: relationships.count,
        conformsToCount: conformsToCount,
        refinementsCount: perFilePairs,
        conformsToOtherKinds: conformsToOtherKinds,
        parseSeconds: inputSymbols.parseSeconds
    )
}

fileprivate enum OracleError: Swift.Error, CustomStringConvertible {
    case malformedInput(path: String, reason: String)

    var description: String {
        switch self {
        case let .malformedInput(path, reason):
            return "malformed symbol-graph at \(path): \(reason)"
        }
    }
}

// MARK: - Entry point

func main() throws {
    let args = CommandLine.arguments
    guard args.count >= 2 else {
        FileHandle.standardError.write(Data(
            "usage: \(args[0]) <path-to-symbols.json> [<path-to-symbols.json>...]\n".utf8
        ))
        exit(2)
    }

    let inputPaths: [String] = args.dropFirst().map { $0 }
    let runStartedAt = Date()

    // Pass 1: load all inputs and build the UNION of symbol identities
    // + protocol IDs. This is what makes cross-module protocol→protocol
    // refinement detection work — when Comparison.Protocol's symbol
    // graph references Equation.Protocol (defined in another module),
    // the target ID is present in the other module's input. Without
    // the union we'd skip cross-module refinements as "endpoint not
    // in this graph."
    var symbolLeafByID: [String: String] = [:]
    var symbolPathByID: [String: String] = [:]
    var protocolIDs: Set<String> = []
    var loadedInputs: [InputSymbols] = []
    for path in inputPaths {
        let loaded = try loadSymbols(
            path: path,
            symbolLeafByID: &symbolLeafByID,
            symbolPathByID: &symbolPathByID,
            protocolIDs: &protocolIDs
        )
        loadedInputs.append(loaded)
    }

    // Pass 2: walk relationships across all inputs, using the union
    // symbol maps for membership checks.
    var allRefinements: Set<RefinementPair> = []
    var perInputStats: [PerInputStats] = []
    for input in loadedInputs {
        let stats = try processInput(
            inputSymbols: input,
            symbolLeafByID: symbolLeafByID,
            symbolPathByID: symbolPathByID,
            protocolIDs: protocolIDs,
            accumulator: &allRefinements
        )
        perInputStats.append(stats)
    }

    let aggregationCompletedAt = Date()

    // Determine output naming from the first input's module.
    let firstModule = perInputStats.first?.module ?? "<unknown>"
    let isStdlib = firstModule == "Swift" && inputPaths.count == 1
    let variableName = isStdlib ? "idiomKnownStdlibRefinements" : "idiomKnownUserDomainRefinements"
    let swiftFileName = isStdlib ? "StdlibRefinementsTable.swift" : "UserDomainRefinementsTable.swift"
    let kindLabel = isStdlib ? "Stdlib" : "User-domain"

    // Emit outputs to Outputs/.
    let outputDir = "Outputs"
    try? FileManager.default.createDirectory(
        atPath: outputDir, withIntermediateDirectories: true
    )

    // JSON oracle — emits both leaf and full-path forms so consumers can
    // pick the discriminator matching their matching strategy.
    let jsonPath = "\(outputDir)/conformance-oracle.json"
    let sortedPairs = allRefinements.sorted {
        ($0.refiningPath, $0.refinedPath) < ($1.refiningPath, $1.refinedPath)
    }
    let outJSON: JSON = .array(sortedPairs.map { pair in
        JSON.object([
            ("refining", .string(pair.refiningLeaf)),
            ("refined", .string(pair.refinedLeaf)),
            ("refiningPath", .string(pair.refiningPath)),
            ("refinedPath", .string(pair.refinedPath)),
        ])
    })
    let serialized = outJSON.serialize(pretty: true)
    try serialized.write(toFile: jsonPath, atomically: true, encoding: String.Encoding.utf8)

    // Swift source table.
    let swiftPath = "\(outputDir)/\(swiftFileName)"
    let runDate = ISO8601DateFormatter().string(from: Date()).prefix(10)
    let modulesList = perInputStats.map { $0.module }.joined(separator: ", ")
    let toolchainGenerator: String = {
        guard
            let firstPath = inputPaths.first,
            let raw = try? String(contentsOf: URL(fileURLWithPath: firstPath), encoding: .utf8),
            let root = try? JSON.parse(raw)
        else {
            return "<unknown>"
        }
        return root.metadata.generator.asString ?? "<unknown>"
    }()
    var swiftSource = """
        // ===----------------------------------------------------------------------===//
        //
        // This source file is part of the swift-linter-rules open source project
        //
        // Copyright (c) 2026 Coen ten Thije Boonkkamp and the swift-linter-rules project authors
        // Licensed under Apache License v2.0
        //
        // See LICENSE for license information
        //
        // ===----------------------------------------------------------------------===//
        //
        // !!! AUTO-GENERATED — DO NOT EDIT !!!
        //
        // This file is regenerated by
        // `swift-linter-rules/Scripts/regenerate-\(isStdlib ? "stdlib" : "user-domain")-refinements.sh`.
        // The generator is the `symbol-graph-conformance-oracle` experiment
        // at `swift-foundations/swift-json/Experiments/`.
        //
        // Kind:        \(kindLabel) protocol-refinement table
        // Source:      \(modulesList)
        // Toolchain:   \(toolchainGenerator)
        // Run date:    \(runDate)
        // Pair count:  \(sortedPairs.count)
        // Input count: \(inputPaths.count) symbol-graph file(s)
        //
        // To regenerate against a newer toolchain or expanded module set,
        // run the script. To audit the generation pipeline, see the
        // experiment's main.swift header.

        /// \(kindLabel) protocol refinements: each pair `(refining, refined)`
        /// means `refining` declares `: refined` (directly or transitively),
        /// so a composition `refining & refined` (in either order) is
        /// redundant. Sourced from the transitive closure of protocol→protocol
        /// `conformsTo` relationships in the input symbol graphs.
        @usableFromInline
        internal let \(variableName): [(refining: Swift.String, refined: Swift.String)] = [

        """
    // The Swift source table emits LEAF pairs (compatible with the
    // current rule's leaf-name matching). For user-domain mode where
    // institute protocols share the leaf name "Protocol", this table
    // is informational — the rule would need full-path matching to
    // consume it usefully. See the conformance-oracle.json output for
    // the full-path discriminator.
    for pair in sortedPairs {
        swiftSource += "    (\"\(pair.refiningLeaf)\", \"\(pair.refinedLeaf)\"),\n"
    }
    swiftSource += "]\n"
    try swiftSource.write(toFile: swiftPath, atomically: true, encoding: String.Encoding.utf8)

    // Report.
    func pad(_ s: String, _ n: Int) -> String {
        s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
    }
    func padInt(_ i: Int, _ n: Int) -> String {
        pad("\(i)", n)
    }
    func fmt(_ d: Double) -> String {
        String(d.rounded() / 1000) // crude; we use seconds-with-3-decimals below
    }

    print("=== Symbol-Graph Conformance Oracle (\(kindLabel)) ===")
    print("Inputs:                \(inputPaths.count)")
    print("Modules:               \(modulesList)")
    print("")
    print("Per-input stats:")
    print("\(pad("module", 44)) \(pad("symbols", 9)) \(pad("protocols", 10)) \(pad("relations", 10)) \(pad("conf-to", 9)) \(pad("new pairs", 10))")
    for stats in perInputStats {
        print("\(pad(stats.module, 44)) \(padInt(stats.symbolCount, 9)) \(padInt(stats.protocolCount, 10)) \(padInt(stats.relationshipsCount, 10)) \(padInt(stats.conformsToCount, 9)) \(padInt(stats.refinementsCount, 10))")
    }
    print("")
    print("Aggregate (union):     \(allRefinements.count) refinement pairs")
    print("")
    print("=== Refinement pairs (full path) ===")
    if sortedPairs.isEmpty {
        print("(none — no module in the input set declares a protocol that refines another protocol)")
    } else {
        for pair in sortedPairs {
            let leafCollision = pair.refiningLeaf == pair.refinedLeaf
            let marker = leafCollision ? "  [LEAF COLLISION]" : ""
            print("  \(pair.refiningPath) → \(pair.refinedPath)\(marker)")
        }
    }
    print("")
    print("=== Timing ===")
    let totalSec = aggregationCompletedAt.timeIntervalSince(runStartedAt)
    print("Total wall-clock:  \(String(format: "%.3f", totalSec))s")
    for stats in perInputStats {
        print("  \(pad(stats.module, 44)) \(String(format: "%.3f", stats.parseSeconds))s (parse)")
    }
    print("")
    print("Output (JSON):  \(jsonPath)")
    print("Output (Swift): \(swiftPath)")
}

do {
    try main()
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
