// swift-tools-version: 6.2

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
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", .upToNextMajor(from: "1.4.0")),
        .package(url: "https://github.com/no-problem-dev/swift-api-contract", .upToNextMajor(from: "1.0.0"))
    ],
    targets: [
        .target(
            name: "APIClient",
            dependencies: [
                .product(name: "APIContract", package: "swift-api-contract")
            ]
        ),
        .testTarget(
            name: "APIClientTests",
            dependencies: ["APIClient"],
            path: "Tests"
        )
    ]
)
