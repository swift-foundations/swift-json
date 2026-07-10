// swift-tools-version: 6.3.3

import PackageDescription

let package = Package(
    name: "swift-json",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "JSON", targets: ["JSON"])
    ],
    dependencies: [
        .package(url: "https://github.com/swift-ietf/swift-rfc-8259.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-parser-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-array-primitives.git", branch: "main"),
        // The Array<S>-over-column tower: the number-lexer scratch buffer is the inline⊕heap small
        // column `Array<Buffer<Storage<Memory.Allocator<Memory.Small<24>>>.Contiguous<Byte>>.Linear>`
        // (the SBO that stays inline up to 24 bytes and spills to heap beyond — the restored
        // `Array.Small<24>` behaviour, now sound because Storage.Contiguous derives its base per
        // access, [MEM-SAFE-029]). Array_Primitives does NOT re-export the tower (exports-narrowing),
        // so each tower layer is an explicit dep + import. (swift-memory-small-primitives transitively
        // brings the heap + inline arms it composes.)
        .package(url: "https://github.com/swift-primitives/swift-buffer-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-buffer-linear-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-storage-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-memory-allocation-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-memory-small-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-byte-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-index-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-ascii-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-ascii-parser-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-coder-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-either-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-foundations/swift-async.git", branch: "main")
    ],
    targets: [
        .target(
            name: "JSON",
            dependencies: [
                .product(name: "RFC 8259", package: "swift-rfc-8259"),
                .product(name: "Parser Error Primitives", package: "swift-parser-primitives"),
                .product(name: "Array Primitives", package: "swift-array-primitives"),
                .product(name: "Array Small Primitive", package: "swift-array-primitives"),
                .product(name: "Buffer Primitive", package: "swift-buffer-primitives"),
                .product(name: "Buffer Linear Primitive", package: "swift-buffer-linear-primitives"),
                .product(name: "Buffer Linear Primitives", package: "swift-buffer-linear-primitives"),
                .product(name: "Storage Primitive", package: "swift-storage-primitives"),
                .product(name: "Storage Contiguous Primitives", package: "swift-storage-primitives"),
                .product(name: "Memory Allocator Primitive", package: "swift-memory-allocation-primitives"),
                .product(name: "Memory Small Primitives", package: "swift-memory-small-primitives"),
                .product(name: "Byte Primitive", package: "swift-byte-primitives"),
                .product(name: "Index Primitives", package: "swift-index-primitives"),
                .product(name: "ASCII Primitives", package: "swift-ascii-primitives"),
                .product(name: "ASCII Decimal Parser Primitives", package: "swift-ascii-parser-primitives"),
                .product(name: "Coder Primitives", package: "swift-coder-primitives"),
                .product(name: "Either Primitives", package: "swift-either-primitives"),
                .product(name: "Async", package: "swift-async")
            ]
        ),
        .testTarget(
            name: "JSON Tests",
            dependencies: [
                "JSON",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("LifetimeDependence"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("LifetimeDependence"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
