import APIContract
import Foundation
import HTTPTransport
import StructuredDataCore

/// The client: it assembles requests, applies auth, maps errors, and emits telemetry — and performs no I/O itself.
///
/// Sending belongs to the injected `HTTPTransport`; retry and rate-limit handling are a
/// decorator wrapped around it; serialization is fixed to swift-structured-data and is
/// deliberately not selectable — `keyStyle` and `dateStrategy` are the whole surface,
/// rather than a coder you pass in.
///
/// One consequence of it being a `struct`: copies share one telemetry channel and one
/// credential, because they hold the same references. Building a second client from the
/// first does not give you a second `events` stream, and does not double the calls your
/// token provider sees. Construct one client per base URL and inject it.
public struct APIClientImpl: APIClient {
    private let baseURL: URL
    private let transport: any HTTPTransport & HTTPStreamingTransport
    private let sendTransport: any HTTPTransport
    private let authToken: AuthToken
    private let timeout: TimeInterval
    private let defaultHeaders: [String: String]
    private let bodyEncoder: any APIBodyEncoder
    private let bodyDecoder: any APIBodyDecoder

    public let events: TelemetryStream<HTTPEvent>
    private let eventObservers: TelemetryObservers<HTTPEvent>

    public let logs: TelemetryStream<HTTPLog>
    private let logObservers: TelemetryObservers<HTTPLog>

    /// Creates a client for one base URL; contracts supply everything that varies per call.
    ///
    /// Two behaviours are worth knowing before choosing arguments.
    ///
    /// **Headers are applied in order, and the last write wins:** `Accept` and
    /// `Content-Type` first, then `defaultHeaders`, then the resolved auth header, then
    /// the group's `commonHeaders`, then the endpoint's `additionalHeaders`. So a
    /// `defaultHeaders` entry can replace `Accept`. The one exception is the credential:
    /// a group or endpoint header naming the same header the contract's `AuthScheme` just
    /// filled fails the call with ``APIError/conflictingAuthHeader(name:)`` rather than
    /// quietly winning.
    ///
    /// **`retryPolicy` and `rateLimitMapping` govern buffered calls only.** SSE calls go
    /// straight to `transport`, so a stream that drops is never retried and no rate-limit
    /// header is read for it.
    ///
    /// - Parameters:
    ///   - baseURL: Prefixes every request; the contract's resolved path is appended. A contract whose path is empty leaves it untouched, which is how a base URL that is already a complete endpoint works.
    ///   - transport: Where bytes actually go. Substituting a mock here exercises the whole request-building path, which a stub `APIClient` does not.
    ///   - authTokenProvider: Consulted when no token has been resolved yet and again whenever one is rejected with a 401; concurrent calls share a single consultation. `nil` sends every request unauthenticated no matter what the contract's `AuthScheme` says.
    ///   - timeout: Per-request timeout in seconds, passed down to the transport.
    ///   - defaultHeaders: Added to every request, and overridable per group and per endpoint.
    ///   - retryPolicy: Governs buffered sends. The default retries nothing, so opt in deliberately.
    ///   - rateLimitMapping: How to read rate-limit headers, so the retry policy can honour the server's `Retry-After` instead of backing off blindly. `nil` ignores them.
    ///   - keyStyle: Applied to request encoding and response decoding alike.
    ///   - dateStrategy: Wire format for `Date` in both directions.
    public init(
        baseURL: URL,
        transport: any HTTPTransport & HTTPStreamingTransport = URLSessionTransport(),
        authTokenProvider: AuthTokenProvider? = nil,
        timeout: TimeInterval = 60,
        defaultHeaders: [String: String] = [:],
        retryPolicy: any RetryPolicy = NoRetry(),
        rateLimitMapping: RateLimitHeaderMapping? = RateLimitHeaderMapping(),
        keyStyle: APIKeyStyle = .default,
        dateStrategy: DateStrategy = .llmAPIDefault
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.sendTransport = RetryingTransport(base: transport, policy: retryPolicy, rateLimitMapping: rateLimitMapping)
        self.authToken = AuthToken(provider: authTokenProvider)
        self.timeout = timeout
        self.defaultHeaders = defaultHeaders
        self.bodyEncoder = BodyCoding.encoder(keyStrategy: keyStyle.encoding, dateStrategy: dateStrategy)
        self.bodyDecoder = BodyCoding.decoder(keyStrategy: keyStyle.decoding, dateStrategy: dateStrategy)

        let eventObservers = TelemetryObservers<HTTPEvent>()
        self.eventObservers = eventObservers
        self.events = TelemetryStream(eventObservers)

        let logObservers = TelemetryObservers<HTTPLog>()
        self.logObservers = logObservers
        self.logs = TelemetryStream(logObservers)
    }

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        try bodyEncoder.encode(value)
    }

    // MARK: - APIExecutable

    /// Runs a contract and returns the decoded output together with the status and headers.
    ///
    /// The full buffered path: build the URL, resolve and attach the token, send through
    /// the retrying transport, emit telemetry, map the failure, decode the body.
    ///
    /// Use this rather than `execute(_:)` when you need the status code or a response
    /// header — a `Location`, an ETag, a pagination cursor. `execute(_:)` is this call
    /// with the metadata discarded.
    ///
    /// - Parameter contract: The endpoint to run.
    /// - Returns: The decoded `Output`, the status code, and the response headers.
    /// - Throws: The group's mapped error if its `decodeError` claims the response, otherwise ``APIError``. A decode failure also emits ``HTTPLog/decodingError(endpoint:error:data:targetType:)`` first, which is the only copy of the offending body.
    public func executeWithResponse<E: APIContract>(_ contract: E) async throws -> APIResponse<E.Output>
        where E.Input == E, E: APIInput
    {
        let endpoint = APIEndpoint(path: E.resolvePath(with: contract), method: E.method)
        let response = try await send(
            endpoint: endpoint, scopes: E.requiredScopes, decodeError: E.Group.decodeError
        ) {
            try await buildRequest(
                method: E.method.rawValue,
                path: E.resolvePath(with: contract),
                queryParameters: contract.queryParameters,
                body: try contract.encodeBody(using: bodyEncoder),
                authScheme: E.auth,
                scopes: E.requiredScopes,
                groupHeaders: E.Group.commonHeaders,
                endpointHeaders: contract.additionalHeaders,
                accept: "application/json"
            )
        }
        do {
            let output = try bodyDecoder.decode(E.Output.self, from: response.body)
            return APIResponse(output: output, statusCode: response.status, headers: dictionary(response.headers))
        } catch {
            logObservers.yield(.decodingError(
                endpoint: endpoint, error: String(describing: error),
                data: response.body, targetType: String(describing: E.Output.self)
            ))
            throw APIError.decodingError(error)
        }
    }

    /// Runs a contract and hands back the response body undecoded.
    ///
    /// For endpoints whose body is not JSON — audio, images, a PDF — or whose JSON does
    /// not fit the contract's `Output`. Sends `Accept: */*` instead of
    /// `application/json`, and the contract's `Output` type is ignored entirely.
    ///
    /// Failure handling is identical to ``executeWithResponse(_:)``: same group error
    /// mapping, same events, same log entries. Only the success path differs.
    ///
    /// - Parameter contract: The endpoint to run.
    /// - Returns: The raw body, the status code, and the response headers.
    /// - Throws: The group's mapped error, otherwise ``APIError``.
    public func executeRaw<E: APIContract>(_ contract: E) async throws -> APIResponse<Data>
        where E.Input == E, E: APIInput
    {
        let endpoint = APIEndpoint(path: E.resolvePath(with: contract), method: E.method)
        let response = try await send(
            endpoint: endpoint, scopes: E.requiredScopes, decodeError: E.Group.decodeError
        ) {
            try await buildRequest(
                method: E.method.rawValue,
                path: E.resolvePath(with: contract),
                queryParameters: contract.queryParameters,
                body: try contract.encodeBody(using: bodyEncoder),
                authScheme: E.auth,
                scopes: E.requiredScopes,
                groupHeaders: E.Group.commonHeaders,
                endpointHeaders: contract.additionalHeaders,
                accept: "*/*"
            )
        }
        return APIResponse(output: response.body, statusCode: response.status, headers: dictionary(response.headers))
    }

    // MARK: - StreamingAPIExecutable

    /// Opens an SSE stream and decodes each message into the contract's `Event` type.
    ///
    /// Empty payloads and the `[DONE]` sentinel are skipped rather than surfaced, so the
    /// stream ends cleanly on a well-behaved server. Nothing is sent until you start
    /// iterating, and abandoning the iteration — `break`, an early `return`, cancelling
    /// the enclosing task — cancels the underlying request.
    ///
    /// This path is deliberately thinner than the buffered one, in ways that matter:
    ///
    /// - **No retries.** `retryPolicy` and `rateLimitMapping` are not in play here.
    /// - **No telemetry.** Nothing reaches `events` or `logs`, including a stream that
    ///   fails outright, so a 401 on a stream will not drive your app-wide logout.
    /// - **No refresh.** The token is resolved once when the stream opens; a 401 here
    ///   does not renew it the way a buffered call's does.
    ///
    /// Failures arrive in the same shape a buffered call's do: the group's `decodeError`
    /// first, then ``APIError``. A `catch APIError.httpError` written for a buffered call
    /// keeps matching when it is reused here.
    ///
    /// - Parameter contract: The streaming endpoint to run.
    /// - Returns: A stream of decoded events; it finishes when the response body ends.
    /// - Throws: Into the stream: the group's mapped error, otherwise ``APIError``. A throwing ``AuthTokenProvider`` still fails with its own error, unwrapped.
    public func execute<E: StreamingAPIContract>(_ contract: E) -> AsyncThrowingStream<E.Event, Error>
        where E.Input == E, E: APIInput
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (request, _) = try await buildRequest(
                        method: E.method.rawValue,
                        path: E.resolvePath(with: contract),
                        queryParameters: contract.queryParameters,
                        body: try contract.encodeBody(using: bodyEncoder),
                        authScheme: E.auth,
                        scopes: E.requiredScopes,
                        groupHeaders: E.Group.commonHeaders,
                        endpointHeaders: contract.additionalHeaders,
                        accept: "text/event-stream"
                    )
                    for try await sse in transport.sseEvents(request) {
                        let payload = sse.data
                        if payload.isEmpty || payload == "[DONE]" { continue }
                        let event = try bodyDecoder.decode(E.Event.self, from: Data(payload.utf8))
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: mapStreamFailure(error, decodeError: E.Group.decodeError))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Opens an SSE stream and yields each message undecoded, event name included.
    ///
    /// The form to use when one stream carries several event types and the meaning of a
    /// message depends on what came before it — Anthropic's message stream, where
    /// `content_block_delta` only makes sense against the block a `content_block_start`
    /// opened. Reading `event` yourself and folding the deltas into state is the point;
    /// ``execute(_:)`` cannot express it, because it decodes every message into one type.
    ///
    /// Like ``execute(_:)`` it retries nothing and emits no telemetry. Unlike it, a
    /// non-2xx status is run through the group's `decodeError` and falls back to
    /// ``APIError``, so the failure you catch has the same shape as a buffered call's.
    ///
    /// - Parameter contract: The endpoint to run. Any contract will do; it does not have to be a `StreamingAPIContract`.
    /// - Returns: A stream of raw server-sent events.
    public func executeEventStream<E: APIContract>(_ contract: E) -> AsyncThrowingStream<SSEEvent, Error>
        where E.Input == E, E: APIInput
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (request, _) = try await buildRequest(
                        method: E.method.rawValue,
                        path: E.resolvePath(with: contract),
                        queryParameters: contract.queryParameters,
                        body: try contract.encodeBody(using: bodyEncoder),
                        authScheme: E.auth,
                        scopes: E.requiredScopes,
                        groupHeaders: E.Group.commonHeaders,
                        endpointHeaders: contract.additionalHeaders,
                        accept: "text/event-stream"
                    )
                    for try await sse in transport.sseEvents(request) {
                        continuation.yield(sse)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: mapStreamFailure(error, decodeError: E.Group.decodeError))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request building

    /// Builds one request, and reports the token it attached so the caller can tell a
    /// refreshed credential from the one the server just rejected.
    private func buildRequest(
        method: String,
        path: String,
        queryParameters: [String: String]?,
        body: Data?,
        authScheme: AuthScheme,
        scopes: [String],
        groupHeaders: [String: String],
        endpointHeaders: [String: String],
        accept: String
    ) async throws -> (request: HTTPRequest, token: String?) {
        // appendingPathComponent("") appends a trailing slash. When the base URL is
        // already a complete endpoint (OpenAI-compatible hosts, where the contract's path
        // is empty by design) that produced `.../chat/completions/`, which Groq rejects
        // with "Unknown request URL". An empty path must leave the base URL alone.
        let requestURL = path.isEmpty ? baseURL : baseURL.appendingPathComponent(path)
        guard var components = URLComponents(
            url: requestURL, resolvingAgainstBaseURL: true
        ) else { throw APIError.invalidURL }

        let token: String?
        switch authScheme {
        case .none: token = nil
        case .bearer, .apiKey, .queryParam: token = try await authToken.value(scopes: scopes)
        }

        var items = components.queryItems ?? []
        if case .queryParam(let name) = authScheme, let token {
            items.append(URLQueryItem(name: name, value: token))
        }
        if let queryParameters, !queryParameters.isEmpty {
            items.append(contentsOf: queryParameters.map { URLQueryItem(name: $0.key, value: $0.value) })
        }
        if !items.isEmpty { components.queryItems = items }
        guard let url = components.url else { throw APIError.invalidURL }

        var headers = HTTPHeaders()
        headers["Accept"] = accept
        if body != nil { headers["Content-Type"] = "application/json" }
        for (key, value) in defaultHeaders { headers[key] = value }

        // The header the credential occupies, and so the one a later header may not take.
        // Nil when nothing was attached, which leaves a group header free to be the
        // credential itself.
        let credentialHeader: String?
        switch authScheme {
        case .none, .queryParam:
            credentialHeader = nil
        case .bearer:
            if let token { headers["Authorization"] = "Bearer \(token)" }
            credentialHeader = token.map { _ in "Authorization" }
        case .apiKey(let headerName):
            if let token { headers[headerName] = token }
            credentialHeader = token.map { _ in headerName }
        }

        for (key, value) in groupHeaders {
            try reject(key, collidingWith: credentialHeader)
            headers[key] = value
        }
        for (key, value) in endpointHeaders {
            try reject(key, collidingWith: credentialHeader)
            headers[key] = value
        }

        return (HTTPRequest(method: method, url: url, headers: headers, body: body, timeout: timeout), token)
    }

    private func reject(_ name: String, collidingWith credentialHeader: String?) throws {
        guard let credentialHeader,
              name.caseInsensitiveCompare(credentialHeader) == .orderedSame
        else { return }
        throw APIError.conflictingAuthHeader(name: credentialHeader)
    }

    /// Sends, and on a 401 gives the token provider one chance to replace the credential.
    ///
    /// The rebuild runs the whole request-building path again, so the renewed token is
    /// attached exactly the way the first one was. A second send happens only when the
    /// provider actually returned a different token — a provider with nothing new to offer
    /// costs no extra round trip, and cannot put the client in a loop.
    private func send(
        endpoint: APIEndpoint,
        scopes: [String],
        decodeError: @Sendable (Int, Data, [String: String], any APIBodyDecoder) -> (any Error)?,
        build: () async throws -> (request: HTTPRequest, token: String?)
    ) async throws -> HTTPResponse {
        let (request, token) = try await build()
        var response = try await transmit(request)

        if response.status == 401, let token {
            let renewed = try await authToken.refreshed(scopes: scopes, rejecting: token)
            if renewed != token {
                response = try await transmit(try await build().request)
            }
        }

        if response.isSuccess {
            logObservers.yield(.success(endpoint: endpoint, statusCode: response.status, data: response.body))
            return response
        }

        logObservers.yield(.httpError(endpoint: endpoint, statusCode: response.status, data: response.body))
        emitEvent(for: response, endpoint: endpoint)
        if let custom = decodeError(response.status, response.body, dictionary(response.headers), bodyDecoder) {
            throw custom
        }
        throw mapToAPIError(statusCode: response.status, data: response.body)
    }

    private func transmit(_ request: HTTPRequest) async throws -> HTTPResponse {
        do {
            return try await sendTransport.send(request)
        // A status error is a response, not a transport failure. Folding it back into
        // one keeps every non-2xx on a single path, so `.httpError` logs and events fire
        // whichever way the transport chose to report the status.
        } catch let error as HTTPStatusError {
            return HTTPResponse(status: error.status, headers: error.headers, body: error.body)
        } catch {
            throw APIError.networkError(error)
        }
    }

    // MARK: - Telemetry / errors

    private func emitEvent(for response: HTTPResponse, endpoint: APIEndpoint) {
        switch response.status {
        case 401: eventObservers.yield(.unauthorized(endpoint: endpoint, data: response.body))
        case 403: eventObservers.yield(.forbidden(endpoint: endpoint, data: response.body))
        case 429:
            let retryAfter = response.headers["retry-after"].flatMap { TimeInterval($0) }
            eventObservers.yield(.rateLimited(endpoint: endpoint, retryAfter: retryAfter, data: response.body))
        case 503: eventObservers.yield(.serviceUnavailable(endpoint: endpoint, data: response.body))
        case 500...599: eventObservers.yield(.serverError(statusCode: response.status, endpoint: endpoint, data: response.body))
        default: break
        }
    }

    /// Puts a streaming failure in the shape a buffered call's failure has, so one `catch`
    /// serves both. Anything this layer did not produce — the auth provider's own error,
    /// an encoding failure, ``APIError/invalidURL`` — is left exactly as it was.
    private func mapStreamFailure(
        _ error: any Error,
        decodeError: @Sendable (Int, Data, [String: String], any APIBodyDecoder) -> (any Error)?
    ) -> any Error {
        switch error {
        case let status as HTTPStatusError:
            return decodeError(status.status, status.body, dictionary(status.headers), bodyDecoder)
                ?? mapToAPIError(statusCode: status.status, data: status.body)
        case is DecodingError:
            return APIError.decodingError(error)
        case is TransportError:
            return APIError.networkError(error)
        default:
            return error
        }
    }

    private func mapToAPIError(statusCode: Int, data: Data) -> APIError {
        switch statusCode {
        case 401: return .unauthorized(data: data)
        case 403: return .forbidden(data: data)
        default: return .httpError(statusCode: statusCode, data: data)
        }
    }

    private func dictionary(_ headers: HTTPHeaders) -> [String: String] {
        headers.pairs.reduce(into: [:]) { $0[$1.name] = $1.value }
    }
}
