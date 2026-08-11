# Changelog

All notable changes to this project are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and this
project adheres to [Semantic Versioning](https://semver.org/). Each section below is
published verbatim as the body of the matching GitHub Release.

## [Unreleased]

### Changed

- Raised the swift-structured-data pin to 3.0.0. That release makes the YAML parser reject
  constructs it does not model instead of silently dropping them; nothing in this package's own
  API changes.


### Changed

- **`APIContract` and `HTTPTransport` are no longer re-exported.** Code that used their
  types through `import APIClient` alone now imports them explicitly. Re-exporting made
  their public surface part of this package's, which forced a major here every time a
  dependency published one, and that major then propagated to every consumer.
- Documentation is English throughout: doc comments, README, this file, and the DocC
  landing page. The landing page carries the full walkthrough and the README links to it
  rather than repeating it.
- CI no longer builds or tests; verification happens locally before a tag is pushed, and
  the workflow only turns a tag into a GitHub Release.

### Added

- `CONTRIBUTING.md`, covering how to verify a change and how a release is cut.
- `.spi.yml`, so Swift Package Index hosts the documentation.

## [3.0.2] - 2026-07-30

### Changed

- Raise the swift-http-transport floor to 1.1.2, picking up the SSE parser's CRLF fix.

## [3.0.1] - 2026-07-30

### Changed

- Widen the accepted swift-structured-data range to `1.3.0..<3.0.0` so consumers already
  on 2.x can resolve.
- Sync the release workflows with the shared templates; the old auto-release-on-merge
  workflow is gone.

## [3.0.0] - 2026-07-19

### Removed

- `APIEndpoint.headers`, `APIEndpoint.body`, and `APIEndpoint.queryItems`. Nothing read
  them — the request is built from the contract — so they described a request that was
  never sent.

### Changed

- `AuthTokenProvider.getToken()` is now `fetchToken()`.

### Added

- A DocC landing page with an overview and curated topics, and an English/Japanese
  README pair.
- DocC builds on macOS 26 / Xcode 26 (Swift 6.2); `/documentation/apiclient` is the
  canonical route.

## [2.3.1] - 2026-06-14

### Fixed

- A contract with an empty path no longer gains a trailing slash. Base URLs that are
  already complete endpoints (OpenAI-compatible hosts) were producing
  `.../chat/completions/`, which Groq rejects with `Unknown request URL`.

## [2.3.0] - 2026-06-13

### Added

- `ScopedAuthTokenProvider`, which receives the endpoint's `requiredScopes` so a provider
  can check the grant before spending a request.

## [2.2.0] - 2026-05-31

### Added

- `executeRaw`, returning the response body as `Data` without decoding it — for audio,
  images, and anything that does not fit the contract's `Output`.

## [2.1.0] - 2026-05-31

### Added

- `executeEventStream`, yielding raw `SSEEvent` values with event names intact, for
  streams that carry several message types. Non-2xx statuses run through the group's
  error mapping.

## [2.0.0] - 2026-05-31

### Changed

- **The transport is injected.** `APIClientImpl` takes any
  `HTTPTransport & HTTPStreamingTransport` in place of a `URLSession`, so tests can
  exercise the real request-building path against a mock.
- **Body coding moved to swift-structured-data and is now internal.** `keyStyle` and
  `dateStrategy` replace the four `JSONEncoder`/`JSONDecoder` strategy parameters, and
  apply symmetrically to encoding and decoding.

### Removed

- The in-package SSE client — `SSEClient`, `SSEClientImpl`, `SSEEvent`, and
  `SSEClient+StreamingAPI` — and `RetryPolicy`. Both now come from swift-http-transport.

## [1.2.1] - 2026-05-30

### Fixed

- `SSEClientImpl` framed data-only SSE messages incorrectly.

## [1.2.0] - 2026-04-18

### Added

- A `keyEncodingStrategy` parameter on `APIClientImpl.init`, defaulting to
  `.useDefaultKeys`. Passing `.convertToSnakeCase` makes encoding symmetric with
  `keyDecodingStrategy: .convertFromSnakeCase`, so payload types no longer need explicit
  `case foo = "foo_bar"` mappings and the naming convention is decided in one place.

## [1.1.2] - 2026-04-07

### Fixed

- Linux build: import `FoundationNetworking`, and restrict the SSE client to Darwin.

## [1.1.1] - 2026-04-07

### Changed

- Pin swift-api-contract to 1.1.1.

## [1.1.0] - 2026-03-08

### Added

- Per-group custom error decoding, `AuthScheme` support, and a retry policy.

## [1.0.13] - 2026-01-11

### Added

- A Server-Sent Events client: `SSEEvent` (data, event, id, retry), the `SSEClient`
  protocol, `SSEClientImpl` on `URLSession` with automatic reconnection, and a
  `StreamingAPIContract` bridge.

## [1.0.12] - 2026-01-03

### Added

- Unit tests.

## [1.0.11] - 2026-01-03

### Changed

- `APIClient` now inherits `APIExecutable`, and `request()` is gone — use `execute()`.
- `HTTPMethod` is renamed `APIMethod`, matching swift-api-contract.
- Updated to Swift 6.2.

## [1.0.10] - 2026-01-01

### Changed

- `HTTPMethod` renamed to `APIMethod` for swift-api-contract 1.0.2.

## [1.0.9] - 2025-12-31

### Added

- swift-api-contract 1.0.0 as a dependency, `APIClient` conforming to `APIExecutor`, and
  `execute<E: APIContract>()` on `APIClientImpl`.

### Changed

- Dropped the duplicate `HTTPMethod` definition in favour of the one in `APIContract`.

## [1.0.8] - 2025-12-05

### Changed

- `events` and `logs` are unicast rather than multicast, built directly on
  `AsyncStream.makeStream()`. Dropping the actor removed the `await`, so
  `for await event in client.events` no longer reads `in await client.events`.

### Removed

- `MulticastStreamSource<Element>`. Multiple subscribers are no longer supported;
  subscribe once, from your DI container.

## [1.0.7] - 2025-12-03

### Added

- An HTTP event stream: `HTTPEvent` for the responses that need an app-wide reaction
  (401, 403, 429, 503, other 5xx), exposed as `APIClient.events`.
- An HTTP log stream: `HTTPLog` for request and response entries, exposed as
  `APIClient.logs`, formatted by `CustomStringConvertible` so `print(log)` is readable.
- `MulticastStreamSource<Element>`, an actor delivering one stream to several subscribers.

### Removed

- The `HTTPLogger` class and the `enableDebugLog` parameter, both superseded by `logs`.

## [1.0.6] - 2025-11-15

### Added

- A `dateEncodingStrategy` parameter on `APIClientImpl`, defaulting to `.iso8601`, so
  request bodies match a Go backend's RFC 3339 dates.
- `encode<T: Encodable>`, applying the client's date strategy to hand-built bodies and
  debug output.

### Changed

- Request bodies are encoded through `encode` rather than a bare `JSONEncoder()`, so
  every POST, PUT, and PATCH gets the configured date strategy.

## [1.0.5] - 2025-11-13

### Added

- A `keyDecodingStrategy` parameter on `APIClientImpl`, defaulting to `.useDefaultKeys`,
  so snake_case responses can be decoded with `.convertFromSnakeCase`.

## [1.0.4] - 2025-11-09

### Fixed

- Release workflow messages.

## [1.0.3] - 2025-11-04

### Added

- DocC documentation, generated and published to GitHub Pages by GitHub Actions, and
  linked from the README.

## [1.0.2] - 2025-11-03

### Changed

- Standardized the README structure.

## [1.0.1] - 2025-11-02

### Added

- A separate `LICENSE` file carrying the MIT text.

### Changed

- README: working examples in place of placeholder comments — quick start, GET, POST with
  a JSON body, query parameters, error handling, authentication, and logging — plus
  badges. The full licence text moved out to `LICENSE`.

## [1.0.0] - 2025-11-02

Initial release: an async/await HTTP client with typed requests and responses, automatic
JSON decoding, per-group error handling, authentication, logging, on iOS 17.0+ and
macOS 14.0+.

[Unreleased]: https://github.com/no-problem-dev/swift-api-client/compare/3.0.2...HEAD
[3.0.2]: https://github.com/no-problem-dev/swift-api-client/compare/3.0.1...3.0.2
[3.0.1]: https://github.com/no-problem-dev/swift-api-client/compare/3.0.0...3.0.1
[3.0.0]: https://github.com/no-problem-dev/swift-api-client/compare/v2.3.1...3.0.0
[2.3.1]: https://github.com/no-problem-dev/swift-api-client/compare/v2.3.0...v2.3.1
[2.3.0]: https://github.com/no-problem-dev/swift-api-client/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/no-problem-dev/swift-api-client/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/no-problem-dev/swift-api-client/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/no-problem-dev/swift-api-client/compare/v1.2.1...v2.0.0
[1.2.1]: https://github.com/no-problem-dev/swift-api-client/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/no-problem-dev/swift-api-client/compare/v1.1.2...v1.2.0
[1.1.2]: https://github.com/no-problem-dev/swift-api-client/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/no-problem-dev/swift-api-client/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.13...v1.1.0
[1.0.13]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.12...v1.0.13
[1.0.12]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.11...v1.0.12
[1.0.11]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.10...v1.0.11
[1.0.10]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.9...v1.0.10
[1.0.9]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.8...v1.0.9
[1.0.8]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.7...v1.0.8
[1.0.7]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.6...v1.0.7
[1.0.6]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/no-problem-dev/swift-api-client/releases/tag/v1.0.0
