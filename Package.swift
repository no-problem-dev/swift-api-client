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
        .package(url: "https://github.com/no-problem-dev/swift-api-contract.git", from: "2.1.0"),
        .package(url: "https://github.com/no-problem-dev/swift-http-transport.git", from: "1.1.0"),
        .package(url: "https://github.com/no-problem-dev/swift-structured-data.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "APIClient",
            dependencies: [
                .product(name: "APIContract", package: "swift-api-contract"),
                .product(name: "HTTPTransport", package: "swift-http-transport"),
                .product(name: "StructuredDataCore", package: "swift-structured-data"),
                .product(name: "JSONParsing", package: "swift-structured-data")
            ]
        ),
        .testTarget(
            name: "APIClientTests",
            dependencies: ["APIClient"],
            path: "Tests"
        )
    ]
)
