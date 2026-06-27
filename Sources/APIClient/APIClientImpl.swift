import APIContract
import Foundation
import HTTPTransport
import StructuredDataCore

/// APIクライアント実装。
///
/// Transport(HTTP送受信)・Codec(直列化)・Resilience(リトライ/ログ)を分離した薄い
/// Orchestrator。送受信は注入された ``HTTPTransport`` を通り、直列化は内部で
/// swift-structured-data に固定される(外部からは選べない=隠蔽)。
public struct APIClientImpl: APIClient {
    private let baseURL: URL
    private let transport: any HTTPTransport & HTTPStreamingTransport
    private let sendTransport: any HTTPTransport
    private let authTokenProvider: AuthTokenProvider?
    private let timeout: TimeInterval
    private let defaultHeaders: [String: String]
    private let bodyEncoder: any APIBodyEncoder
    private let bodyDecoder: any APIBodyDecoder

    public let events: AsyncStream<HTTPEvent>
    private let eventContinuation: AsyncStream<HTTPEvent>.Continuation

    public let logs: AsyncStream<HTTPLog>
    private let logContinuation: AsyncStream<HTTPLog>.Continuation

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
        self.authTokenProvider = authTokenProvider
        self.timeout = timeout
        self.defaultHeaders = defaultHeaders
        self.bodyEncoder = BodyCoding.encoder(keyStrategy: keyStyle.encoding, dateStrategy: dateStrategy)
        self.bodyDecoder = BodyCoding.decoder(keyStrategy: keyStyle.decoding, dateStrategy: dateStrategy)
        (self.events, self.eventContinuation) = AsyncStream.makeStream(of: HTTPEvent.self, bufferingPolicy: .unbounded)
        (self.logs, self.logContinuation) = AsyncStream.makeStream(of: HTTPLog.self, bufferingPolicy: .unbounded)
    }

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        try bodyEncoder.encode(value)
    }

    // MARK: - APIExecutable

    public func executeWithResponse<E: APIContract>(_ contract: E) async throws -> APIResponse<E.Output>
        where E.Input == E, E: APIInput
    {
        let endpoint = APIEndpoint(path: E.resolvePath(with: contract), method: E.method)
        let request = try await buildRequest(
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

        let response = try await send(request, endpoint: endpoint, decodeError: E.Group.decodeError)
        do {
            let output = try bodyDecoder.decode(E.Output.self, from: response.body)
            return APIResponse(output: output, statusCode: response.status, headers: dictionary(response.headers))
        } catch {
            logContinuation.yield(.decodingError(
                endpoint: endpoint, error: String(describing: error),
                data: response.body, targetType: String(describing: E.Output.self)
            ))
            throw APIError.decodingError(error)
        }
    }

    /// レスポンスボディを JSON デコードせず生の `Data` で返す。音声/画像などバイナリ応答や、
    /// 型付きデコードに乗らない応答に使う。非 2xx は group の `decodeError` でマップする。
    public func executeRaw<E: APIContract>(_ contract: E) async throws -> APIResponse<Data>
        where E.Input == E, E: APIInput
    {
        let endpoint = APIEndpoint(path: E.resolvePath(with: contract), method: E.method)
        let request = try await buildRequest(
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
        let response = try await send(request, endpoint: endpoint, decodeError: E.Group.decodeError)
        return APIResponse(output: response.body, statusCode: response.status, headers: dictionary(response.headers))
    }

    // MARK: - StreamingAPIExecutable

    public func execute<E: StreamingAPIContract>(_ contract: E) -> AsyncThrowingStream<E.Event, Error>
        where E.Input == E, E: APIInput
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try await buildRequest(
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
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 生の ``SSEEvent``(イベント名 + データ)をそのまま流す。Anthropic のように
    /// 複数イベント型 + 状態蓄積を伴うストリームは、型付き ``execute`` ではなくこちらを使い、
    /// プロバイダ側の accumulator で解釈する。非 2xx は group の `decodeError` でマップする。
    public func executeEventStream<E: APIContract>(_ contract: E) -> AsyncThrowingStream<SSEEvent, Error>
        where E.Input == E, E: APIInput
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try await buildRequest(
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
                } catch let error as HTTPStatusError {
                    let mapped = E.Group.decodeError(
                        statusCode: error.status, data: error.body,
                        headers: dictionary(error.headers), decoder: bodyDecoder
                    ) ?? mapToAPIError(statusCode: error.status, data: error.body)
                    continuation.finish(throwing: mapped)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request building

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
    ) async throws -> HTTPRequest {
        // path が空の場合 appendingPathComponent("") は末尾スラッシュを付与し、
        // 完全 URL を baseURL に持つ契約(OpenAI 互換など)で `.../chat/completions/` の
        // ような不正 URL を生む。空パスは baseURL をそのまま使う。
        let requestURL = path.isEmpty ? baseURL : baseURL.appendingPathComponent(path)
        guard var components = URLComponents(
            url: requestURL, resolvingAgainstBaseURL: true
        ) else { throw APIError.invalidURL }

        var items = components.queryItems ?? []
        if case .queryParam(let name) = authScheme, let token = try await resolveToken(scopes: scopes) {
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

        switch authScheme {
        case .none, .queryParam:
            break
        case .bearer:
            if let token = try await resolveToken(scopes: scopes) { headers["Authorization"] = "Bearer \(token)" }
        case .apiKey(let headerName):
            if let token = try await resolveToken(scopes: scopes) { headers[headerName] = token }
        }
        for (key, value) in groupHeaders { headers[key] = value }
        for (key, value) in endpointHeaders { headers[key] = value }

        return HTTPRequest(method: method, url: url, headers: headers, body: body, timeout: timeout)
    }

    /// 認証トークンを取得する。プロバイダがスコープ対応なら必要スコープを渡す。
    private func resolveToken(scopes: [String]) async throws -> String? {
        if let scoped = authTokenProvider as? ScopedAuthTokenProvider {
            return try await scoped.fetchToken(scopes: scopes)
        }
        return try await authTokenProvider?.fetchToken()
    }

    private func send(
        _ request: HTTPRequest,
        endpoint: APIEndpoint,
        decodeError: @Sendable (Int, Data, [String: String], any APIBodyDecoder) -> (any Error)?
    ) async throws -> HTTPResponse {
        let response: HTTPResponse
        do {
            response = try await sendTransport.send(request)
        } catch let error as HTTPStatusError {
            response = HTTPResponse(status: error.status, headers: error.headers, body: error.body)
        } catch {
            throw APIError.networkError(error)
        }

        if response.isSuccess {
            logContinuation.yield(.success(endpoint: endpoint, statusCode: response.status, data: response.body))
            return response
        }

        logContinuation.yield(.httpError(endpoint: endpoint, statusCode: response.status, data: response.body))
        emitEvent(for: response, endpoint: endpoint)
        if let custom = decodeError(response.status, response.body, dictionary(response.headers), bodyDecoder) {
            throw custom
        }
        throw mapToAPIError(statusCode: response.status, data: response.body)
    }

    // MARK: - Telemetry / errors

    private func emitEvent(for response: HTTPResponse, endpoint: APIEndpoint) {
        switch response.status {
        case 401: eventContinuation.yield(.unauthorized(endpoint: endpoint, data: response.body))
        case 403: eventContinuation.yield(.forbidden(endpoint: endpoint, data: response.body))
        case 429:
            let retryAfter = response.headers["retry-after"].flatMap { TimeInterval($0) }
            eventContinuation.yield(.rateLimited(endpoint: endpoint, retryAfter: retryAfter, data: response.body))
        case 503: eventContinuation.yield(.serviceUnavailable(endpoint: endpoint, data: response.body))
        case 500...599: eventContinuation.yield(.serverError(statusCode: response.status, endpoint: endpoint, data: response.body))
        default: break
        }
    }

    private func mapToAPIError(statusCode: Int, data: Data) -> APIError {
        switch statusCode {
        case 401, 403: return .unauthorized
        default: return .httpError(statusCode: statusCode, data: data)
        }
    }

    private func dictionary(_ headers: HTTPHeaders) -> [String: String] {
        headers.pairs.reduce(into: [:]) { $0[$1.name] = $1.value }
    }
}
