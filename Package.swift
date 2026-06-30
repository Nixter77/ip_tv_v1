// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

var products: [Product] = [
    // 1. Library for tests and reuse.
    .library(
        name: "IPTVPlayer",
        targets: ["IPTVPlayer"]
    )
]

var targets: [Target] = [
    // Core application/library target.
    .target(
        name: "IPTVPlayer",
        dependencies: [],
        path: "Sources"
    ),
    // Unit tests.
    .testTarget(
        name: "IPTVPlayerTests",
        dependencies: ["IPTVPlayer"],
        path: "Tests"
    ),
]

#if os(macOS)
products.append(
    // 2. Executable graphical macOS SwiftUI application.
    .executable(
        name: "IPTVPlayerApp",
        targets: ["IPTVPlayerApp"]
    )
)

targets.append(
    // Executable target with the app entry point.
    .executableTarget(
        name: "IPTVPlayerApp",
        dependencies: ["IPTVPlayer"],
        path: "App"
    )
)
#endif

let package = Package(
    name: "IPTVPlayer",
    platforms: [
        .macOS(.v14)
    ],
    products: products,
    dependencies: [],
    targets: targets
)
