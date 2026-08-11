# ``APIClient``

Run typed endpoint contracts over HTTP and SSE, with one place to configure sending, authentication, and serialization.

## Overview

`APIClient` sits between an app and a REST or SSE backend. It owns no I/O: sending is a
`HTTPTransport` you inject, retry and rate limiting are a decorator around it, and JSON
coding is fixed to swift-structured-data. What is left — assembling the URL, resolving
the credential, mapping the failure, emitting telemetry — is what ``APIClientImpl`` does.

Endpoints come from `APIContract`. A contract declares its method, path, body, and output
type, and the compiler then enforces that a call site cannot ask for a response shape the
endpoint does not produce. Buffered calls and streaming calls run through the same
configuration, so the two cannot drift apart in key style, date format, or authentication.

## Getting started

### Declare a group and an endpoint

A group holds what a family of endpoints shares: the base path, the authentication
scheme, and how the API's error bodies map to Swift errors.

```swift
import APIClient
import APIContract

enum CatalogAPI: APIContractGroup {
    static let basePath = "/v1"
    static let auth: AuthScheme = .bearer
    static let endpoints: [EndpointDescriptor] = []

    // Claim the statuses you can say something better about than "HTTP 422".
    static func decodeError(
        statusCode: Int, data: Data,
        headers: [String: String], decoder: any APIBodyDecoder
    ) -> (any Error)? {
        guard statusCode == 422 else { return nil }
        return try? decoder.decode(ValidationFailure.self, from: data)
    }
}

struct Product: Codable, Sendable {
    let id: String
    let displayName: String
}

struct GetProduct: APIContract, APIInput {
    typealias Group = CatalogAPI
    typealias Input = Self
    typealias Output = Product

    static let method: APIMethod = .get
    static let subPath = "/products/{id}"

    let id: String
    var pathParameters: [String: String] { ["id": id] }

    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { nil }
    static func decode(
        pathParameters: [String: String], queryParameters: [String: String],
        body: Data?, decoder: any APIBodyDecoder
    ) throws -> Self { Self(id: pathParameters["id"] ?? "") }
}
```

`decode` exists so a server can reconstruct the request from a contract. In a client-only
app nothing calls it; return whatever satisfies the compiler.

### Build the client once

Retry policies live in swift-http-transport and contract types in swift-api-contract;
this package re-exports neither, so import what you name.

```swift
import APIClient
import HTTPTransport   // ExponentialBackoff, and any custom transport

let client = APIClientImpl(
    baseURL: URL(string: "https://api.example.com")!,
    authTokenProvider: KeychainTokenProvider(),
    defaultHeaders: ["X-Client-Version": Bundle.main.shortVersion],
    retryPolicy: ExponentialBackoff(maxAttempts: 3),
    keyStyle: .snakeCase
)
```

`keyStyle: .snakeCase` maps `displayName` to `display_name` when encoding *and* when
decoding, so `Product` above needs no `CodingKeys`. `retryPolicy` applies to buffered
calls only; streaming takes a shorter path, described below.

### Run it

```swift
let product = try await client.execute(GetProduct(id: "sku-42"))

// Reach for executeWithResponse when the status code or a header carries meaning.
let page = try await client.executeWithResponse(ListProducts(cursor: cursor))
let next = page.headers["x-next-cursor"]
```

### Catch in the right order

The group's `decodeError` wins: when it claims a response, its error is thrown *instead
of* an ``APIError``, so a `catch APIError.httpError` for that status never runs.

```swift
do {
    let product = try await client.execute(GetProduct(id: id))
    show(product)
} catch let failure as ValidationFailure {   // 1. what CatalogAPI mapped
    show(failure.fieldErrors)
} catch APIError.networkError {              // 2. what this package throws
    showOfflineBanner()
} catch APIError.httpError(let status, _) {
    report(status)
} catch {                                    // 3. everything else
    report(error)
}
```

``APIError/unauthorized(data:)`` and ``APIError/forbidden(data:)`` are separate, and each
carries the body the server sent — so "sign in again" is distinguishable from "this account
may not do that" at the `catch` itself.

### Handle 401 once, not everywhere

```swift
Task {
    for await event in client.events {
        switch event {
        case .unauthorized:
            await session.signOut()
        case .forbidden(_, let body):
            await showUpgradePrompt(reason: body)
        case .rateLimited(_, let retryAfter, _):
            await backOff(for: retryAfter ?? 30)
        case .serviceUnavailable:
            await router.showMaintenance()
        case .serverError(let status, let endpoint, _):
            report(status, endpoint.path)
        }
    }
}
```

Every observer sees every event, so a second task iterating `events` receives copies rather
than taking them from the first. Nothing is kept for an observer that does not exist yet: a
client nobody observes retains no response bodies at all, and an observer that starts late
sees what is emitted from then on. `logs` works the same way and carries every completed
request. See ``TelemetryStream``.

### Streaming runs a shorter path

``APIClientImpl/execute(_:)`` decodes each server-sent message into one event type;
``APIClientImpl/executeEventStream(_:)`` hands them over undecoded, event name included,
for streams that carry several message types.

```swift
for try await chunk in client.execute(StreamCompletion(prompt: prompt)) {
    transcript.append(chunk.delta)
}
```

Both send on first iteration and cancel the request when iteration stops. Neither
retries, and neither emits `events` or `logs` — including when the stream fails, so a
401 on a stream will not reach the app-wide handler above. Handle it at the call site.

## Topics

### Running contracts

- ``APIClientImpl``
- ``APIClient``

### Authentication

- ``AuthTokenProvider``
- ``ScopedAuthTokenProvider``

### Serialization

- ``APIKeyStyle``
- ``DateStrategy``

### Failures and telemetry

- ``APIError``
- ``HTTPEvent``
- ``HTTPLog``
- ``APIEndpoint``
