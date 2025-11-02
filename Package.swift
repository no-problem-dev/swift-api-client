// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "APIClient",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "APIClient",
            targets: ["APIClient"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "APIClient",
            dependencies: []
        ),
        .testTarget(
            name: "APIClientTests",
            dependencies: ["APIClient"],
            path: "Tests"
        )
    ]
)
