// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-json",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        .library(name: "JSON", targets: ["JSON"]),
    ],
    dependencies: [
        .package(path: "../../swift-standards/swift-rfc-8259"),
        .package(path: "../swift-async"),
    ],
    targets: [
        .target(
            name: "JSON",
            dependencies: [
                .product(name: "RFC 8259", package: "swift-rfc-8259"),
                .product(name: "Async", package: "swift-async"),
            ]
        ),
        .testTarget(
            name: "JSON Tests",
            dependencies: ["JSON"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
