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
