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
        .package(path: "../swift-async")
    ],
    targets: [
        .target(
            name: "JSON",
            dependencies: [
                .product(name: "RFC 8259", package: "swift-rfc-8259"),
                .product(name: "Async", package: "swift-async")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableExperimentalFeature("SuppressedAssociatedTypesWithDefaults"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
