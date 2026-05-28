// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "IPTVPlayer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // 1. Библиотека для линковки и тестирования
        .library(
            name: "IPTVPlayer",
            targets: ["IPTVPlayer"]
        ),
        // 2. Исполняемое графическое macOS SwiftUI приложение
        .executable(
            name: "IPTVPlayerApp",
            targets: ["IPTVPlayerApp"]
        )
    ],
    dependencies: [],
    targets: [
        // Основной библиотечный таргет со всем кодом приложения
        .target(
            name: "IPTVPlayer",
            dependencies: [],
            path: "Sources"
        ),
        // Исполняемый таргет с точкой входа, запускающий приложение
        .executableTarget(
            name: "IPTVPlayerApp",
            dependencies: ["IPTVPlayer"],
            path: "App"
        ),
        // Таргет юнит-тестов
        .testTarget(
            name: "IPTVPlayerTests",
            dependencies: ["IPTVPlayer"],
            path: "Tests"
        ),
    ]
)
