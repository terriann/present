// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Present",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "PresentCore", targets: ["PresentCore"]),
        .executable(name: "present-cli", targets: ["PresentCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.12.0"),
    ],
    targets: [
        .target(
            name: "PresentCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/PresentCore"
        ),
        .executableTarget(
            name: "PresentCLI",
            dependencies: [
                "PresentCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/PresentCLI"
        ),
        .testTarget(
            name: "PresentCoreTests",
            dependencies: [
                "PresentCore",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/PresentCoreTests"
        ),
        .testTarget(
            name: "PresentCLITests",
            dependencies: [
                "PresentCore",
                "PresentCLI",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/PresentCLITests"
        ),
    ]
)
