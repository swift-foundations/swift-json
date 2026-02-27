// swift-tools-version: 6.2

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
        .package(path: "../../swift-standards/swift-rfc-8259"),
        .package(path: "../../swift-primitives/swift-parser-primitives"),
        .package(path: "../swift-async")
    ],
    targets: [
        .target(
            name: "JSON",
            dependencies: [
                .product(name: "RFC 8259", package: "swift-rfc-8259"),
                .product(name: "Parser Error Primitives", package: "swift-parser-primitives"),
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
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableExperimentalFeature("SuppressedAssociatedTypesWithDefaults"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
