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
