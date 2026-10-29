// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swift6: [SwiftSetting] = [
    .swiftLanguageMode(.v6)
]

var products: [Product] = [
    .library(
        name: "IPTVPlayer",
        targets: ["IPTVPlayer"]
    )
]

var targets: [Target] = [
    .target(
        name: "IPTVPlayer",
        dependencies: [],
        path: "Sources",
        swiftSettings: swift6
    ),
    .testTarget(
        name: "IPTVPlayerTests",
        dependencies: ["IPTVPlayer"],
        path: "Tests",
        resources: [
            .copy("Fixtures")
        ],
        swiftSettings: swift6
    ),
]

#if os(macOS)
products.append(
    .executable(
        name: "IPTVPlayerApp",
        targets: ["IPTVPlayerApp"]
    )
)

targets.append(
    .executableTarget(
        name: "IPTVPlayerApp",
        dependencies: ["IPTVPlayer"],
        path: "App",
        swiftSettings: swift6
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
