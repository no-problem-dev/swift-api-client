English | [日本語](./README.ja.md)

# swift-api-client

A lightweight Swift HTTP API client with async/await support.

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-brightgreen.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

📚 **[Full Documentation](https://no-problem-dev.github.io/swift-api-client/documentation/apiclient/)**

## Overview

`swift-api-client` is a package for making HTTP API calls in Swift applications simply and type-safely. It supports iOS and macOS platforms with modern Swift concurrency.

Built on the `APIContract` protocol from [swift-api-contract](https://github.com/no-problem-dev/swift-api-contract), it guarantees request/response consistency with compile-time type checking.

### Key Features

- **Modern async/await API** — Full use of Swift 6.0 concurrency
- **Type-safe requests/responses** — Compile-time type checking via `APIContract`
- **Automatic JSON decoding** — Simple response handling with `Codable`
- **Flexible error handling** — Custom error decoding definable per API group
- **Authentication support** — Bearer / ApiKey / QueryParam auth via token provider
- **HTTP event stream** — Critical events (auth errors, rate limiting, etc.) delivered via `AsyncStream`
- **HTTP log stream** — Monitor all requests/responses via `AsyncStream`
- **SSE streaming** — Typed and raw Server-Sent Events streams
- **Cross-platform** — iOS and macOS support

## Dependencies

| Package | Purpose |
|---|---|
| [swift-api-contract](https://github.com/no-problem-dev/swift-api-contract) | API contract type definitions (`APIContract` / `APIContractGroup`, etc.) |
| [swift-http-transport](https://github.com/no-problem-dev/swift-http-transport) | HTTP send/receive / retry / SSE |
| [swift-structured-data](https://github.com/no-problem-dev/swift-structured-data) | JSON encoding and decoding |

## Requirements

- iOS 17.0+
- macOS 14.0+
- Swift 6.0+

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-api-client.git", from: "3.0.0")
]
```

Or in Xcode:
1. File > Add Package Dependencies
2. Enter the package URL: `https://github.com/no-problem-dev/swift-api-client.git`
3. Select version: `2.3.1` or later

## Quick Start

This package defines requests with types that conform to the `APIContract` protocol.

```swift
import APIClient
import APIContract

// 1. Define your response type
struct User: Codable, Sendable {
    let id: Int
    let name: String
}

// 2. Define an API group (shared settings)
enum UserAPI: APIContractGroup {
    static let basePath = "/v1"
    static let auth: AuthScheme = .bearer
    static let endpoints: [EndpointDescriptor] = []
    static func decodeError(
        statusCode: Int, data: Data,
        headers: [String: String], decoder: any APIBodyDecoder
    ) -> (any Error)? { nil }
}

// 3. Define the endpoint contract
struct GetUser: APIContract, APIInput {
    typealias Group = UserAPI
    typealias Input = Self
    typealias Output = User
    static let method: APIMethod = .get
    static let subPath = "/users/1"
    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { nil }
    static func decode(
        pathParameters: [String: String],
        queryParameters: [String: String],
        body: Data?, decoder: any APIBodyDecoder
    ) throws -> Self { Self() }
}

// 4. Create a client and execute the request
let client = APIClientImpl(baseURL: URL(string: "https://api.example.com")!)
let response = try await client.executeWithResponse(GetUser())
print(response.output.name)  // User.name
```

## Usage

### POST Request (with JSON body)

```swift
struct CreateUserBody: Codable, Sendable {
    let name: String
    let email: String
}

struct CreateUser: APIContract, APIInput {
    typealias Group = UserAPI
    typealias Input = Self
    typealias Output = User
    static let method: APIMethod = .post
    static let subPath = "/users"
    let body: CreateUserBody
    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? {
        try encoder.encode(body)
    }
    static func decode(
        pathParameters: [String: String], queryParameters: [String: String],
        body: Data?, decoder: any APIBodyDecoder
    ) throws -> Self { fatalError("server-only") }
}

let response = try await client.executeWithResponse(
    CreateUser(body: CreateUserBody(name: "Ada", email: "ada@example.com"))
)
let newUser = response.output
```

### Error Handling

```swift
do {
    let response = try await client.executeWithResponse(GetUser())
    print(response.output.name)
} catch APIError.unauthorized {
    print("Authentication error")
} catch APIError.networkError(let error) {
    print("Network error: \(error.localizedDescription)")
} catch APIError.httpError(let statusCode, _) {
    print("HTTP error: \(statusCode)")
} catch APIError.decodingError(let error) {
    print("Decoding error: \(error.localizedDescription)")
} catch {
    print("Unexpected error: \(error)")
}
```

### Using an Authentication Token

```swift
// Implement a token provider
struct MyTokenProvider: AuthTokenProvider {
    func fetchToken() async throws -> String? {
        // Token retrieval logic (e.g., from Keychain)
        return "your-auth-token"
    }
}

// Pass the token provider when creating the client
let client = APIClientImpl(
    baseURL: URL(string: "https://api.example.com")!,
    authTokenProvider: MyTokenProvider()
)
// Authorization: Bearer header is added automatically on each request
```

### Binary Response (audio, images)

```swift
// executeRaw returns raw Data without JSON decoding
let response = try await client.executeRaw(GetAudioContract())
let audioData = response.output  // Data
```

### SSE Streaming

Typed stream (single event type):

```swift
for try await event in client.execute(StreamContract()) {
    print(event.delta)
}
```

Raw stream (multiple event types, e.g., Anthropic):

```swift
for try await sse in client.executeEventStream(GetStreamContract()) {
    print(sse.event ?? "message", sse.data)
}
```

### Monitoring HTTP Events

Monitor critical HTTP responses (401, 403, 429, 503, 5xx) application-wide:

```swift
Task {
    for await event in client.events {
        switch event {
        case .unauthorized:
            await authManager.handleLogout()
        case .rateLimited(_, let retryAfter, _):
            print("Rate limited: retry after \(retryAfter ?? 0)s")
        case .serviceUnavailable:
            await router.showMaintenanceScreen()
        default:
            break
        }
    }
}
```

### Monitoring HTTP Logs

```swift
// Debug console output (formatted via CustomStringConvertible)
Task {
    for await log in client.logs {
        print(log)
    }
}

// Custom handling (e.g., sending to Analytics)
Task {
    for await log in client.logs {
        switch log {
        case .success(let endpoint, let statusCode, _):
            analytics.trackSuccess(endpoint: endpoint.path, statusCode: statusCode)
        case .httpError(let endpoint, let statusCode, _):
            analytics.trackError(endpoint: endpoint.path, statusCode: statusCode)
        case .decodingError(let endpoint, _, _, let targetType):
            analytics.trackDecodingError(endpoint: endpoint.path, type: targetType)
        }
    }
}
```

## License

This project is released under the MIT License. See [LICENSE](LICENSE) for details.

## Support

For bug reports or feature requests, please [open an issue on GitHub](https://github.com/no-problem-dev/swift-api-client/issues).
