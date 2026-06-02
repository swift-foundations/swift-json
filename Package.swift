// swift-tools-version: 6.3.1

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
