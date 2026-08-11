English | [日本語](./README.ja.md)

# swift-api-client

An HTTP client for Swift apps that catches calls which no longer match your API at compile time, and handles authentication, retries and error reporting once for both plain and streaming responses.

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+%20%7C%20Linux-blue.svg)
![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-brightgreen.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## Overview

Endpoints are declared as types conforming to `APIContract` from
[swift-api-contract](https://github.com/no-problem-dev/swift-api-contract), which carries
the method, path, body, and output type. A call site cannot then ask for a response shape
the endpoint does not produce.

The client itself performs no I/O. Sending is an injectable transport, so a test can
exercise real URL assembly and header precedence against a mock; retry and rate limiting
are a decorator around it; JSON coding is fixed, and configured through `keyStyle` and
`dateStrategy` rather than by passing a coder.

- Buffered and SSE calls share one transport, codec, and credential, so they cannot drift apart
- Authentication resolved per request through a token provider you implement
- 401, 403, 429, 503 and other 5xx also delivered as an app-wide `AsyncStream`, so logout and maintenance screens are written once
- Per-group error decoding, so an API's own error body becomes your own Swift error type
- Retry with backoff that honours `Retry-After`

## Quick Start

```swift
import APIClient

let client = APIClientImpl(
    baseURL: URL(string: "https://api.example.com")!,
    keyStyle: .snakeCase
)

let product = try await client.execute(GetProduct(id: "sku-42"))

for try await chunk in client.execute(StreamCompletion(prompt: prompt)) {
    transcript.append(chunk.delta)
}
```

`GetProduct` and `StreamCompletion` are contracts. Declaring one, mapping an API's errors
onto Swift errors, and observing the event stream are all in the documentation.

## Documentation

**[API reference and guide](https://no-problem-dev.github.io/swift-api-client/documentation/apiclient/)** —
the full walkthrough from declaring a contract to handling 401 once for the whole app.

## Requirements

iOS 17.0+ · macOS 14.0+ · Linux · Swift 6.0+

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-api-client.git", from: "3.0.0")
]
```

Or in Xcode: **File > Add Package Dependencies**, then enter
`https://github.com/no-problem-dev/swift-api-client.git`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).
