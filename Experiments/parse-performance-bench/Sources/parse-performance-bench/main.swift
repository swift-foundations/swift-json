// Parse-performance bench for swift-json.
//
// Standing measurement + verification harness used by the Tier-0/1/3/4
// parse-performance research. See Package.swift for mode docs and the
// research arc at swift-foundations/swift-json/Research/parse-performance.md.
//
// Foundation import: this experiment is the Foundation-vs-swift-json
// comparison harness; production swift-json Sources/ remains
// Foundation-free.

import Foundation
import JSON
import Dictionary_Ordered_Primitives
import Hash_Primitives

// MARK: - Schema for codable-lookup mode
//
// Minimal Symbol Graph schema covering the fields the canonical
// workload's traversal pattern actually touches:
//   symbols[].kind.identifier   — String
//   symbols[].identifier.precise — String
//   symbols[].pathComponents     — [String]
//
// Defined at file scope so both Foundation Decodable and swift-json
// JSON.Serializable can extend it.

struct SymbolKind: Decodable, JSON.Serializable {
    let identifier: String

    static func deserialize(_ json: JSON) throws(JSON.Error) -> SymbolKind {
        return SymbolKind(identifier: String(json.identifier))
    }

    static func serialize(_ value: SymbolKind) -> JSON {
        ["identifier": .string(value.identifier)]
    }

    static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> SymbolKind {
        try events.expectObjectStart()
        var identifier: String? = nil
        while let token = try events.next() {
            if token == .objectEnd { break }
            if token == .comma { continue }
            guard token == .string else {
                throw .invalidSyntax(message: "expected object key", location: events.position().location)
            }
            let key = try events.currentString()
            try events.expectColon()
            switch key {
            case "identifier":
                identifier = try String.deserialize(events: &events)
            default:
                try events.skipValue()
            }
        }
        guard let identifier = identifier else {
            throw .missingKey("identifier")
        }
        return SymbolKind(identifier: identifier)
    }
}

struct SymbolIdentifier: Decodable, JSON.Serializable {
    let precise: String

    static func deserialize(_ json: JSON) throws(JSON.Error) -> SymbolIdentifier {
        return SymbolIdentifier(precise: String(json.precise))
    }

    static func serialize(_ value: SymbolIdentifier) -> JSON {
        ["precise": .string(value.precise)]
    }

    static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> SymbolIdentifier {
        try events.expectObjectStart()
        var precise: String? = nil
        while let token = try events.next() {
            if token == .objectEnd { break }
            if token == .comma { continue }
            guard token == .string else {
                throw .invalidSyntax(message: "expected object key", location: events.position().location)
            }
            let key = try events.currentString()
            try events.expectColon()
            switch key {
            case "precise":
                precise = try String.deserialize(events: &events)
            default:
                try events.skipValue()
            }
        }
        guard let precise = precise else {
            throw .missingKey("precise")
        }
        return SymbolIdentifier(precise: precise)
    }
}

struct Symbol: Decodable, JSON.Serializable {
    let kind: SymbolKind
    let identifier: SymbolIdentifier
    let pathComponents: [String]

    static func deserialize(_ json: JSON) throws(JSON.Error) -> Symbol {
        let kind = try SymbolKind(json: json.kind)
        let identifier = try SymbolIdentifier(json: json.identifier)
        let pathComponents = try [String](json: json.pathComponents)
        return Symbol(kind: kind, identifier: identifier, pathComponents: pathComponents)
    }

    static func serialize(_ value: Symbol) -> JSON {
        [
            "kind": SymbolKind.serialize(value.kind),
            "identifier": SymbolIdentifier.serialize(value.identifier),
            "pathComponents": .array(value.pathComponents.map { .string($0) })
        ]
    }

    /// Opt-in event-grain deserialize. The wedge: only 3 of ~9 keys
    /// per symbol are declared; the rest go through skipValue() which
    /// walks bytes without materialising values. This is the §4.6
    /// end-to-end example translated to the Symbol schema.
    static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> Symbol {
        try events.expectObjectStart()
        var kind: SymbolKind? = nil
        var identifier: SymbolIdentifier? = nil
        var pathComponents: [String]? = nil
        while let token = try events.next() {
            if token == .objectEnd { break }
            if token == .comma { continue }
            guard token == .string else {
                throw .invalidSyntax(message: "expected object key", location: events.position().location)
            }
            let key = try events.currentString()
            try events.expectColon()
            switch key {
            case "kind":
                kind = try SymbolKind.deserialize(events: &events)
            case "identifier":
                identifier = try SymbolIdentifier.deserialize(events: &events)
            case "pathComponents":
                pathComponents = try [String].deserialize(events: &events)
            default:
                try events.skipValue() // ← the wedge
            }
        }
        guard let kind = kind, let identifier = identifier,
              let pathComponents = pathComponents else {
            throw .missingKey("kind/identifier/pathComponents")
        }
        return Symbol(kind: kind, identifier: identifier, pathComponents: pathComponents)
    }
}

struct SymbolGraph: Decodable, JSON.Serializable {
    let symbols: [Symbol]

    static func deserialize(_ json: JSON) throws(JSON.Error) -> SymbolGraph {
        let symbols = try [Symbol](json: json.symbols)
        return SymbolGraph(symbols: symbols)
    }

    static func serialize(_ value: SymbolGraph) -> JSON {
        ["symbols": .array(value.symbols.map { Symbol.serialize($0) })]
    }

    static func deserialize(events: inout JSON.Span.EventStream) throws(JSON.Error) -> SymbolGraph {
        try events.expectObjectStart()
        var symbols: [Symbol]? = nil
        while let token = try events.next() {
            if token == .objectEnd { break }
            if token == .comma { continue }
            guard token == .string else {
                throw .invalidSyntax(message: "expected object key", location: events.position().location)
            }
            let key = try events.currentString()
            try events.expectColon()
            switch key {
            case "symbols":
                symbols = try [Symbol].deserialize(events: &events)
            default:
                try events.skipValue()
            }
        }
        guard let symbols = symbols else {
            throw .missingKey("symbols")
        }
        return SymbolGraph(symbols: symbols)
    }
}

func mono() -> Double {
    var ts = timespec()
    clock_gettime(CLOCK_MONOTONIC, &ts)
    return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
}

func pad(_ s: String, _ n: Int) -> String {
    s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
}

func report(_ label: String, _ seconds: Double) {
    print("\(pad(label, 50)) \(String(format: "%8.3f", seconds))s")
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: \(args[0]) <path> [iters] [mode]\n".utf8))
    exit(2)
}
let path = args[1]
let iters = args.count >= 3 ? (Int(args[2]) ?? 1) : 1
let mode = args.count >= 4 ? args[3] : "all"

guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
    print("could not read \(path)")
    exit(1)
}
let mb = Double(data.count) / 1048576.0
print("input size: \(data.count) bytes (\(String(format: "%.2f", mb)) MB)")
print("iterations: \(iters), mode: \(mode)")
print("")

let stringForm: String = String(decoding: data, as: UTF8.self)
let bytesForm: [UInt8] = .init(data)
print("prepared String + [UInt8] forms")
print("")

// FLOOR: byte iteration
if mode == "all" || mode == "floor" {
    do {
        let t0 = mono()
        for _ in 0..<iters {
            var sum: UInt64 = 0
            for b in data { sum = sum &+ UInt64(b) }
            if sum == 0 { print("(DCE)") }
        }
        report("[FLOOR]   byte-iterate Data", mono() - t0)
    }
    do {
        let t0 = mono()
        for _ in 0..<iters {
            var sum: UInt64 = 0
            for b in bytesForm { sum = sum &+ UInt64(b) }
            if sum == 0 { print("(DCE)") }
        }
        report("[FLOOR]   byte-iterate [UInt8]", mono() - t0)
    }
}

// Foundation: JSONSerialization
if mode == "all" || mode == "foundation" {
    let t0 = mono()
    for _ in 0..<iters {
        _ = try JSONSerialization.jsonObject(with: data, options: [])
    }
    report("Foundation.JSONSerialization.jsonObject(with:)", mono() - t0)
}

// swift-json: String path
if mode == "all" || mode == "swift-json-string" {
    let t0 = mono()
    for _ in 0..<iters {
        _ = try JSON.parse(stringForm)
    }
    report("swift-json JSON.parse(String)", mono() - t0)
}

// swift-json: bytes path
if mode == "all" || mode == "swift-json-bytes" {
    let t0 = mono()
    for _ in 0..<iters {
        _ = try JSON.parse(bytesForm)
    }
    report("swift-json JSON.parse([UInt8])", mono() - t0)
}

// CROSSOVER mode: storage micro-bench. For each object size N in
// {1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024} build a representative
// (key, value) container in three storage shapes and measure raw
// lookup throughput. Pre-randomised lookup keys; tight loop; minimal
// overhead. Answers: at what N does Dictionary.Ordered beat the
// current [(String, Value)] linear scan? At what N does it beat
// Swift.Dictionary?
if mode == "crossover" {
    print("=== CROSSOVER: storage micro-bench by object size ===")
    print("Per-row: ns/lookup at object-size N, over 10 000 lookups against random hit keys.")
    print("")
    let sizes = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024]
    let nLookups = 10_000
    print(pad("size", 6), pad("array(curr)", 14), pad("Swift.Dict", 14), pad("Dict.Ordered", 14), pad("array/Ordered", 14))
    for size in sizes {
        // Pre-generate keys; "k_NNN" pattern roughly matches real-world short keys.
        let keys = (0..<size).map { "k_\($0)" }
        let values = (0..<size).map { $0 }
        let array: [(String, Int)] = zip(keys, values).map { ($0.0, $0.1) }
        let swiftDict: Swift.Dictionary<String, Int> = Swift.Dictionary(uniqueKeysWithValues: zip(keys, values).map { ($0, $1) })
        var orderedDict = Dictionary<String, Int>.Ordered()
        for (k, v) in zip(keys, values) { orderedDict.set(k, v) }

        // Pre-generate lookup keys (always hits).
        var rng = SystemRandomNumberGenerator()
        let lookupKeys: [String] = (0..<nLookups).map { _ in keys[Int.random(in: 0..<size, using: &rng)] }

        // Bench: array linear scan
        let t0 = mono()
        var sinkA = 0
        for k in lookupKeys {
            if let v = array.first(where: { $0.0 == k })?.1 { sinkA &+= v }
        }
        let tA = mono() - t0
        if sinkA == 0 { print("(DCE A)") }

        // Bench: Swift.Dictionary
        let t1 = mono()
        var sinkS = 0
        for k in lookupKeys {
            if let v = swiftDict[k] { sinkS &+= v }
        }
        let tS = mono() - t1
        if sinkS == 0 { print("(DCE S)") }

        // Bench: Dictionary.Ordered
        let t2 = mono()
        var sinkO = 0
        for k in lookupKeys {
            if let v = orderedDict[k] { sinkO &+= v }
        }
        let tO = mono() - t2
        if sinkO == 0 { print("(DCE O)") }

        // ns/lookup
        let nsA = Int(tA * 1e9 / Double(nLookups))
        let nsS = Int(tS * 1e9 / Double(nLookups))
        let nsO = Int(tO * 1e9 / Double(nLookups))
        let ratio = String(format: "%.2f×", tA / tO)
        print(pad("\(size)", 6), pad("\(nsA) ns", 14), pad("\(nsS) ns", 14), pad("\(nsO) ns", 14), pad(ratio, 14))
    }
    print("")
    print("Reading: where Dict.Ordered < array(curr), the storage change wins on that size.")
    print("Where array/Ordered > 1, the linear scan is faster than Dict.Ordered.")
}

// SYNTHETIC-LOOKUP mode: build a JSON document of `iters` objects each
// with N keys, parse with both parsers, time the lookup pass. Mirrors
// the canonical workload but lets us scale N to find the end-to-end
// crossover including the Any-cast cost in Foundation's path.
if mode == "synthetic-lookup" {
    print("=== SYNTHETIC-LOOKUP: end-to-end at varying object size ===")
    print("Per-row: lookup ms (parse excluded) for swift-json vs Foundation at object-size N, summed over 5000 objects.")
    print("")
    let sizes = [1, 4, 8, 16, 32, 64, 128, 256]
    let nObjects = 5_000
    print(pad("size", 6), pad("swift-json", 12), pad("Foundation", 12), pad("Fnd/swift-json", 16))
    for size in sizes {
        // Build a JSON string: an array of N-key objects.
        // Each object: {"k_0":0, "k_1":1, ..., "k_{N-1}":N-1}
        var doc = "["
        for i in 0..<nObjects {
            if i > 0 { doc.append(",") }
            doc.append("{")
            for j in 0..<size {
                if j > 0 { doc.append(",") }
                doc.append("\"k_\(j)\":\(j)")
            }
            doc.append("}")
        }
        doc.append("]")
        let docData = Data(doc.utf8)

        let sjRoot = try JSON.parse(doc)
        let fnRoot = try JSONSerialization.jsonObject(with: docData, options: []) as! [Any]

        guard let sjArr = sjRoot.array else { print("sj array missing"); continue }

        // Lookup: read `k_0` from every object (single hop).
        // Single lookup per object isolates the lookup cost from
        // multi-hop chain noise.
        let lookupKey = "k_0"

        let t0 = mono()
        var sinkSJ: Int = 0
        for o in sjArr {
            if let i = Int(o[lookupKey]) {
                sinkSJ &+= i
            }
        }
        let tSJ = mono() - t0
        if sinkSJ == 0 { print("(DCE SJ)") }

        let t1 = mono()
        var sinkFN: Int = 0
        for o in fnRoot {
            if let dict = o as? [String: Any], let i = dict[lookupKey] as? Int {
                sinkFN &+= i
            }
        }
        let tFN = mono() - t1
        if sinkFN == 0 { print("(DCE FN)") }

        let msSJ = String(format: "%.3f ms", tSJ * 1000)
        let msFN = String(format: "%.3f ms", tFN * 1000)
        let ratio = String(format: "%.2f×", tFN / tSJ)
        print(pad("\(size)", 6), pad(msSJ, 12), pad(msFN, 12), pad(ratio, 16))
    }
}

// SIZE-DIST mode: walk the parsed swift-json tree once and build a
// histogram of object sizes. Answers: what's the actual distribution
// of keys-per-object in this real-world workload?
if mode == "size-dist" {
    print("=== SIZE-DIST: object-size histogram for the input ===")
    let root = try JSON.parse(stringForm)
    var sizeHistogram: [Int: Int] = [:]
    var totalObjects: Int = 0
    var totalKeys: Int = 0
    var maxSize: Int = 0

    func walk(_ json: JSON) {
        if let obj = json.object {
            let n = obj.count
            sizeHistogram[n, default: 0] &+= 1
            totalObjects &+= 1
            totalKeys &+= n
            if n > maxSize { maxSize = n }
            for (_, v) in obj { walk(v) }
        } else if let arr = json.array {
            for v in arr { walk(v) }
        }
    }
    walk(root)

    let mean = Double(totalKeys) / Double(totalObjects)
    print("Total objects: \(totalObjects)")
    print("Total keys:    \(totalKeys)")
    print("Mean keys/object: \(String(format: "%.2f", mean))")
    print("Max keys/object:  \(maxSize)")
    print("")
    print(pad("size", 6), pad("count", 10), pad("% of total", 12), "histogram")
    let sortedSizes = sizeHistogram.keys.sorted()
    for s in sortedSizes {
        let count = sizeHistogram[s]!
        let pct = 100.0 * Double(count) / Double(totalObjects)
        let bar = String(repeating: "#", count: min(Int(pct / 2.0), 50))
        print(pad("\(s)", 6), pad("\(count)", 10), pad(String(format: "%.2f%%", pct), 12), bar)
    }
}

// LOOKUP mode: measures the lookup-heavy traversal pattern that the
// symbol-graph oracle uses. Parses the file ONCE per parser, then runs
// the access pattern `iters` times. Wall-clock excludes parse; lookup
// throughput is what's reported.
//
// The access pattern mirrors `symbol-graph-conformance-oracle`:
//   for each symbol in root.symbols:
//     - read .kind.identifier
//     - read .identifier.precise
//     - read .pathComponents (array length only — counts the inner reads)
//
// Establishes the pre-L1-1 baseline for v2 architecture's measurement
// gate. Re-run after the storage change in L1-1 to verify the gap
// closed.
if mode == "lookup" {
    print("=== LOOKUP: parse once, traverse N times ===")
    print("(Parse times excluded from lookup measurement; tree built once per parser.)")
    print("")

    // Parse once with each. Time the parses themselves separately for
    // context, but the LOOKUP measurement is just the traversal loop.
    let pT0 = mono()
    let sjRoot = try JSON.parse(stringForm)
    let pT1 = mono()
    let fnRoot = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
    let pT2 = mono()
    report("(once)  swift-json parse", pT1 - pT0)
    report("(once)  Foundation parse", pT2 - pT1)
    print("")

    // Pre-cache the symbols arrays so we don't repeat the top-level lookup.
    guard let sjSymbols = sjRoot.symbols.array,
          let fnSymbols = fnRoot["symbols"] as? [Any] else {
        print("symbols array missing")
        exit(1)
    }
    let symbolCount = sjSymbols.count
    guard symbolCount == fnSymbols.count else {
        print("symbol counts diverge: swift-json=\(symbolCount) Foundation=\(fnSymbols.count)")
        exit(1)
    }
    print("symbol count: \(symbolCount)")
    print("")

    // swift-json traversal
    do {
        let t0 = mono()
        var sink: Int = 0
        for _ in 0..<iters {
            for sym in sjSymbols {
                if sym.kind.identifier.isString { sink &+= 1 }
                if sym.identifier.precise.isString { sink &+= 1 }
                if let pc = sym.pathComponents.array { sink &+= pc.count }
            }
        }
        if sink == 0 { print("(DCE)") }
        report("swift-json lookup pass (×\(iters))", mono() - t0)
    }

    // Foundation traversal — same shape, Any-cast at each hop
    do {
        let t0 = mono()
        var sink: Int = 0
        for _ in 0..<iters {
            for sym in fnSymbols {
                guard let symDict = sym as? [String: Any] else { continue }
                if let kind = symDict["kind"] as? [String: Any],
                   kind["identifier"] is String { sink &+= 1 }
                if let ident = symDict["identifier"] as? [String: Any],
                   ident["precise"] is String { sink &+= 1 }
                if let pc = symDict["pathComponents"] as? [Any] { sink &+= pc.count }
            }
        }
        if sink == 0 { print("(DCE)") }
        report("Foundation lookup pass (×\(iters))", mono() - t0)
    }

    print("")
    print("Equivalent reads per iteration: 3 × \(symbolCount) = \(3 * symbolCount)")
    print("Total reads over \(iters) iters: \(3 * symbolCount * iters)")
}

// CODABLE-LOOKUP mode: schema-known typed-decode comparison.
//
// The standard `lookup` mode compares JSONSerialization (untyped Any
// + per-hop casts) against swift-json's typed dynamic-member-lookup.
// This mode runs the schema-known counterpart: Foundation's
// JSONDecoder + Codable struct vs swift-json's JSON.Serializable
// extension. Both produce a native Swift struct after parse+decode;
// post-decode lookup is native struct member access on both sides
// (no casts, no dynamic dispatch).
//
// Three measurements per parser:
//   1. Full parse + decode (single shot from bytes/string to struct)
//   2. Lookup pass over the decoded struct (native access)
//   3. Combined wall-clock for parse-once-then-lookup-N-times
//
// Expected: lookup is ≈ equal because both sides do native struct
// access. Parse+decode may differ — Foundation's JSONDecoder is
// selective (parses only fields the Decodable declares); swift-json
// parses the full tree first via JSON.parse(...) then extracts.
if mode == "codable-lookup" {
    print("=== CODABLE-LOOKUP: schema-known typed-decode comparison ===")
    print("Symbol schema: kind.identifier + identifier.precise + pathComponents")
    print("Foundation:  JSONDecoder().decode(SymbolGraph.self, from: data)")
    print("swift-json:  SymbolGraph(jsonBytes: bytesForm)")
    print("")

    // Time parse+decode for each parser (single iteration).
    let p0 = mono()
    let fnGraph = try JSONDecoder().decode(SymbolGraph.self, from: data)
    let p1 = mono()
    let sjGraph = try SymbolGraph(jsonBytes: bytesForm)
    let p2 = mono()
    report("(once)  Foundation parse+decode", p1 - p0)
    report("(once)  swift-json parse+decode", p2 - p1)
    print("")

    // Validate equivalent results
    let fnCount = fnGraph.symbols.count
    let sjCount = sjGraph.symbols.count
    guard fnCount == sjCount else {
        print("symbol counts diverge: fn=\(fnCount) sj=\(sjCount)")
        exit(1)
    }
    print("symbol count: \(fnCount) (match: \(fnCount == sjCount))")
    print("")

    // Foundation lookup pass — native struct access
    do {
        let t0 = mono()
        var sink: Int = 0
        for _ in 0..<iters {
            for sym in fnGraph.symbols {
                sink &+= sym.kind.identifier.count
                sink &+= sym.identifier.precise.count
                sink &+= sym.pathComponents.count
            }
        }
        if sink == 0 { print("(DCE FN)") }
        report("Foundation lookup pass (×\(iters))", mono() - t0)
    }

    // swift-json lookup pass — native struct access (same shape)
    do {
        let t0 = mono()
        var sink: Int = 0
        for _ in 0..<iters {
            for sym in sjGraph.symbols {
                sink &+= sym.kind.identifier.count
                sink &+= sym.identifier.precise.count
                sink &+= sym.pathComponents.count
            }
        }
        if sink == 0 { print("(DCE SJ)") }
        report("swift-json lookup pass (×\(iters))", mono() - t0)
    }

    print("")
    print("Equivalent reads per iteration: 3 × \(fnCount) = \(3 * fnCount)")
    print("Total reads over \(iters) iters: \(3 * fnCount * iters)")
}

// CODABLE-LOOKUP-EVENT-GRAIN mode (Phase A1 of streaming-deserialize).
//
// Three measurements:
//   1. Foundation parse+decode (control)
//   2. swift-json status-quo SymbolGraph(jsonBytes:) (control)
//   3. swift-json event-grain SymbolGraph.from(eventDecodingJsonBytes:)
//      with opt-in deserialize(events:) — the wedge
//
// Plus the §4.3 default-fallback non-regression axis: a non-opt-in
// String.from(eventDecodingJsonBytes:) on a small JSON-encoded string
// should match status-quo init(jsonBytes:) performance within noise.
// Existing String, Int, Array, Dictionary conformers DO override
// deserialize(events:); to exercise the default-fallback path we
// build a small bespoke conformer DefaultFallbackProbe that
// inherits the default.
//
// Expected (per streaming-json-deserialize-comparative-analysis.md
// v1.0.1 §9.3 binding A2 gate):
//   - axis (a): opt-in SymbolGraph closes most of the 37% gap to
//     Foundation: target ≤1.10× Foundation parse+decode.
//   - axis (b): non-opt-in default-fallback path within ±5% of the
//     existing codable-lookup mode's swift-json baseline.
struct DefaultFallbackProbe: JSON.Serializable {
    let name: String
    let age: Int

    static func serialize(_ value: DefaultFallbackProbe) -> JSON {
        ["name": .string(value.name), "age": .number(value.age)]
    }

    static func deserialize(_ json: JSON) throws(JSON.Error) -> DefaultFallbackProbe {
        let name = String(json.name)
        guard !name.isEmpty else { throw .missingKey("name") }
        guard let age = Int(json.age) else { throw .missingKey("age") }
        return DefaultFallbackProbe(name: name, age: age)
    }
    // Deliberately does NOT override deserialize(events:) — exercises
    // the §4.3 default-fallback path with the short-circuit.
}

if mode == "codable-lookup-event-grain" {
    print("=== CODABLE-LOOKUP-EVENT-GRAIN: opt-in fast path ===")
    print("Symbol schema: kind.identifier + identifier.precise + pathComponents")
    print("Foundation:  JSONDecoder().decode(SymbolGraph.self, from: data)")
    print("swift-json status-quo:  SymbolGraph(jsonBytes: bytesForm)")
    print("swift-json event-grain: SymbolGraph.from(eventDecodingJsonBytes: bytesForm)")
    print("")

    // Time parse+decode for each path (single iteration).
    let p0 = mono()
    let fnGraph = try JSONDecoder().decode(SymbolGraph.self, from: data)
    let p1 = mono()
    let sjStatusQuoGraph = try SymbolGraph(jsonBytes: bytesForm)
    let p2 = mono()
    let sjEventGrainGraph = try SymbolGraph.from(eventDecodingJsonBytes: bytesForm)
    let p3 = mono()
    let foundationTime = p1 - p0
    let statusQuoTime = p2 - p1
    let eventGrainTime = p3 - p2
    report("(once)  Foundation parse+decode", foundationTime)
    report("(once)  swift-json status-quo parse+decode", statusQuoTime)
    report("(once)  swift-json EVENT-GRAIN parse+decode", eventGrainTime)
    print("")
    print("Ratios:")
    print("  status-quo / Foundation:  \(String(format: "%.3f", statusQuoTime / foundationTime))x")
    print("  event-grain / Foundation: \(String(format: "%.3f", eventGrainTime / foundationTime))x   [A2 axis (a)]")
    print("  event-grain / status-quo: \(String(format: "%.3f", eventGrainTime / statusQuoTime))x   (wedge close)")
    print("")

    // Validate equivalent results
    let fnCount = fnGraph.symbols.count
    let sjStatusQuoCount = sjStatusQuoGraph.symbols.count
    let sjEventGrainCount = sjEventGrainGraph.symbols.count
    guard fnCount == sjStatusQuoCount, sjStatusQuoCount == sjEventGrainCount else {
        print("symbol counts diverge: fn=\(fnCount) sj-sq=\(sjStatusQuoCount) sj-eg=\(sjEventGrainCount)")
        exit(1)
    }
    print("symbol count: \(fnCount) (all three paths match)")
    print("")

    // Lookup pass parity check across all three.
    do {
        let t0 = mono()
        var sink: Int = 0
        for _ in 0..<iters {
            for sym in fnGraph.symbols {
                sink &+= sym.kind.identifier.count
                sink &+= sym.identifier.precise.count
                sink &+= sym.pathComponents.count
            }
        }
        if sink == 0 { print("(DCE FN)") }
        report("Foundation lookup pass (×\(iters))", mono() - t0)
    }
    do {
        let t0 = mono()
        var sink: Int = 0
        for _ in 0..<iters {
            for sym in sjStatusQuoGraph.symbols {
                sink &+= sym.kind.identifier.count
                sink &+= sym.identifier.precise.count
                sink &+= sym.pathComponents.count
            }
        }
        if sink == 0 { print("(DCE SJ-SQ)") }
        report("swift-json status-quo lookup pass (×\(iters))", mono() - t0)
    }
    do {
        let t0 = mono()
        var sink: Int = 0
        for _ in 0..<iters {
            for sym in sjEventGrainGraph.symbols {
                sink &+= sym.kind.identifier.count
                sink &+= sym.identifier.precise.count
                sink &+= sym.pathComponents.count
            }
        }
        if sink == 0 { print("(DCE SJ-EG)") }
        report("swift-json event-grain lookup pass (×\(iters))", mono() - t0)
    }

    print("")
    print("=== A2 axis (b): default-fallback non-regression probe ===")
    print("Tiny JSON {\"name\":\"x\",\"age\":1}; 100 000 iters; both paths.")
    let probeJSON = #"{"name":"Alice","age":30}"#
    let probeBytes: [UInt8] = Swift.Array(probeJSON.utf8)
    let probeIters = 100_000

    do {
        let t0 = mono()
        var sink: Int = 0
        for _ in 0..<probeIters {
            let v = try DefaultFallbackProbe(jsonBytes: probeBytes)
            sink &+= v.age
        }
        if sink == 0 { print("(DCE probe-SQ)") }
        let dt = mono() - t0
        report("DefaultFallbackProbe status-quo (×\(probeIters))", dt)
    }
    do {
        let t0 = mono()
        var sink: Int = 0
        for _ in 0..<probeIters {
            let v = try DefaultFallbackProbe.from(eventDecodingJsonBytes: probeBytes)
            sink &+= v.age
        }
        if sink == 0 { print("(DCE probe-EG)") }
        let dt = mono() - t0
        report("DefaultFallbackProbe default-fallback (×\(probeIters))", dt)
    }

    print("")
    print("Equivalent reads per iteration: 3 × \(fnCount) = \(3 * fnCount)")
    print("Total reads over \(iters) iters: \(3 * fnCount * iters)")
}

// SANITY mode: verify both parsers actually built the tree by extracting
// known fields. Run with `... 1 sanity` to engage.
if mode == "sanity" {
    print("=== SANITY: extract module.name from both parsers ===")
    do {
        let json = try JSON.parse(stringForm)
        let moduleName: String? = {
            guard json.isObject else { return nil }
            let modJSON = json.module
            return modJSON.isObject ? String(modJSON.name) : nil
        }()
        print("  swift-json parsed; json.module.name = \(moduleName ?? "<missing>")")
    }
    do {
        let parsed = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = parsed as? [String: Any],
              let mod = root["module"] as? [String: Any],
              let name = mod["name"] as? String else {
            print("  Foundation parsed; module.name = <missing or wrong shape>")
            exit(1)
        }
        print("  Foundation parsed; module.name = \(name)")
    }
    print("")
    print("If both lines print the same module name, both parsers built non-trivial trees.")
    print("")

    // Now compare wall-clock with tree-traversal included.
    print("=== SANITY: parse + traverse + assertion ===")
    let countSymbolsSwiftJSON: (String) throws -> Int = { s in
        let root = try JSON.parse(s)
        guard let arr = root.symbols.array else { return -1 }
        return arr.count
    }
    let countSymbolsFoundation: (Data) throws -> Int = { d in
        let parsed = try JSONSerialization.jsonObject(with: d, options: [])
        guard let root = parsed as? [String: Any],
              let arr = root["symbols"] as? [Any] else { return -1 }
        return arr.count
    }

    do {
        let t0 = mono()
        for _ in 0..<iters {
            let n = try countSymbolsSwiftJSON(stringForm)
            if n < 0 { fatalError("swift-json: symbols not array") }
        }
        report("swift-json parse + symbols.count", mono() - t0)
    }
    do {
        let t0 = mono()
        for _ in 0..<iters {
            let n = try countSymbolsFoundation(data)
            if n < 0 { fatalError("Foundation: symbols not array") }
        }
        report("Foundation parse + symbols.count", mono() - t0)
    }

    // Confirm same count
    let nA = try countSymbolsSwiftJSON(stringForm)
    let nB = try countSymbolsFoundation(data)
    print("")
    print("symbol count: swift-json=\(nA) Foundation=\(nB) match=\(nA == nB)")
}

// EQUIV mode: deep tree equivalence check across multiple fields.
if mode == "equiv" {
    let sj = try JSON.parse(stringForm)
    let fn = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]

    print("=== top-level keys ===")
    if let obj = sj.object {
        let keys = obj.map { $0.key }.sorted()
        print("  swift-json: \(keys)")
    }
    print("  Foundation: \(fn.keys.sorted())")

    print("\n=== symbols.count ===")
    let sjSymCount = sj.symbols.array?.count ?? -1
    let fnSymCount = (fn["symbols"] as? [Any])?.count ?? -1
    print("  swift-json: \(sjSymCount)")
    print("  Foundation: \(fnSymCount)")
    print("  match: \(sjSymCount == fnSymCount && sjSymCount > 0)")

    print("\n=== relationships.count ===")
    let sjRelCount = sj.relationships.array?.count ?? -1
    let fnRelCount = (fn["relationships"] as? [Any])?.count ?? -1
    print("  swift-json: \(sjRelCount)")
    print("  Foundation: \(fnRelCount)")
    print("  match: \(sjRelCount == fnRelCount && sjRelCount > 0)")

    print("\n=== module.name ===")
    let sjModName = String(sj.module.name)
    let fnModName = ((fn["module"] as? [String: Any])?["name"] as? String) ?? "?"
    print("  swift-json: \(sjModName)")
    print("  Foundation: \(fnModName)")
    print("  match: \(sjModName == fnModName && !sjModName.isEmpty)")

    print("\n=== symbols[0].kind.identifier ===")
    let s0 = sj.symbols[0]
    if let arr = fn["symbols"] as? [Any],
       let f0 = arr.first as? [String: Any],
       let f0kind = f0["kind"] as? [String: Any],
       let f0id = f0kind["identifier"] as? String {
        let sjK = String(s0.kind.identifier)
        print("  swift-json: \(sjK)")
        print("  Foundation: \(f0id)")
        print("  match: \(sjK == f0id && !sjK.isEmpty)")
    }

    print("\n=== relationships[0].kind ===")
    let r0sj = sj.relationships[0]
    if let arr = fn["relationships"] as? [Any],
       let r0fn = arr.first as? [String: Any],
       let r0kind = r0fn["kind"] as? String {
        let sjK = String(r0sj.kind)
        print("  swift-json: \(sjK)")
        print("  Foundation: \(r0kind)")
        print("  match: \(sjK == r0kind && !sjK.isEmpty)")
    }

    print("\n=== last symbol's pathComponents ===")
    let lastIdx = sjSymCount - 1
    let sN = sj.symbols[lastIdx]
    if let fNarr = fn["symbols"] as? [Any],
       let fN = fNarr[lastIdx] as? [String: Any] {
        let sjPaths = sN.pathComponents.array?.compactMap { $0.isString ? String($0) : nil } ?? []
        let fnPaths = (fN["pathComponents"] as? [Any])?.compactMap { $0 as? String } ?? []
        print("  swift-json: \(sjPaths)")
        print("  Foundation: \(fnPaths)")
        print("  match: \(sjPaths == fnPaths && !sjPaths.isEmpty)")
    }
}

print("")
print("done.")
