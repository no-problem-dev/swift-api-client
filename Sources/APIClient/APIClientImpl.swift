import APIContract
import Foundation

/// APIクライアント実装
public struct APIClientImpl: APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let authTokenProvider: AuthTokenProvider?
    private let timeout: TimeInterval
    private let defaultHeaders: [String: String]
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let retryPolicy: RetryPolicy

    public let events: AsyncStream<HTTPEvent>
    private let eventContinuation: AsyncStream<HTTPEvent>.Continuation

    public let logs: AsyncStream<HTTPLog>
    private let logContinuation: AsyncStream<HTTPLog>.Continuation

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        authTokenProvider: AuthTokenProvider? = nil,
        timeout: TimeInterval = 60.0,
        defaultHeaders: [String: String] = [:],
        retryPolicy: RetryPolicy = NoRetry(),
        keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys,
        dateEncodingStrategy: JSONEncoder.DateEncodingStrategy? = nil,
        dateDecodingStrategy: JSONDecoder.DateDecodingStrategy? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.authTokenProvider = authTokenProvider
        self.timeout = timeout
        self.defaultHeaders = defaultHeaders
        self.retryPolicy = retryPolicy

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = dateEncodingStrategy ?? Self.defaultDateEncodingStrategy()
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = keyDecodingStrategy
        decoder.dateDecodingStrategy = dateDecodingStrategy ?? Self.defaultDateDecodingStrategy()
        self.decoder = decoder

        (self.events, self.eventContinuation) = AsyncStream.makeStream(of: HTTPEvent.self, bufferingPolicy: .unbounded)
        (self.logs, self.logContinuation) = AsyncStream.makeStream(of: HTTPLog.self, bufferingPolicy: .unbounded)
    }

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    // MARK: - APIExecutable

    public func executeWithResponse<E: APIContract>(_ contract: E) async throws -> APIResponse<E.Output>
        where E.Input == E, E: APIInput
    {
        let endpoint = try makeEndpoint(from: contract)
        let (data, httpResponse) = try await performRequest(
            endpoint,
            authScheme: E.auth,
            groupHeaders: E.Group.commonHeaders,
            endpointHeaders: contract.additionalHeaders,
            decodeError: E.Group.decodeError
        )

        do {
            let output = try decoder.decode(E.Output.self, from: data)
            return APIResponse(
                output: output,
                statusCode: httpResponse.statusCode,
                headers: Self.extractHeaders(from: httpResponse)
            )
        } catch {
            logContinuation.yield(.decodingError(
                endpoint: endpoint,
                error: String(describing: error),
                data: data,
                targetType: String(describing: E.Output.self)
            ))
            throw APIError.decodingError(error)
        }
    }

    public func execute<E: APIContract>(_ contract: E) async throws -> E.Output
        where E.Input == E, E: APIInput
    {
        try await executeWithResponse(contract).output
    }

    public func execute<E: APIContract>(_ contract: E) async throws
        where E.Input == E, E.Output == EmptyOutput, E: APIInput
    {
        _ = try await executeWithResponse(contract)
    }

    // MARK: - Private

    private func makeEndpoint<E: APIContract>(from contract: E) throws -> APIEndpoint
        where E.Input == E, E: APIInput
    {
        let path = E.resolvePath(with: contract)

        let queryItems: [URLQueryItem]?
        if let params = contract.queryParameters, !params.isEmpty {
            queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        } else {
            queryItems = nil
        }

        let body = try contract.encodeBody(using: encoder)

        return APIEndpoint(
            path: path,
            method: E.method,
            body: body,
            queryItems: queryItems
        )
    }

    private func performRequest(
        _ endpoint: APIEndpoint,
        authScheme: AuthScheme,
        groupHeaders: [String: String],
        endpointHeaders: [String: String],
        decodeError: @Sendable (Int, Data, [String: String], JSONDecoder) -> (any Error)?
    ) async throws -> (Data, HTTPURLResponse) {
        let maxAttempts = retryPolicy.maxRetries + 1

        for attempt in 1...maxAttempts {
            let result: Result<(Data, HTTPURLResponse), Error>
            do {
                result = .success(try await sendRequest(
                    endpoint,
                    authScheme: authScheme,
                    groupHeaders: groupHeaders,
                    endpointHeaders: endpointHeaders
                ))
            } catch {
                // ネットワークエラー（接続失敗等）のみリトライ対象
                if attempt < maxAttempts {
                    let delay = retryPolicy.delay(for: attempt, retryAfter: nil)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw APIError.networkError(error)
            }

            let (data, httpResponse) = try result.get()
            let statusCode = httpResponse.statusCode

            guard !(200...299).contains(statusCode) else {
                logContinuation.yield(.success(endpoint: endpoint, statusCode: statusCode, data: data))
                return (data, httpResponse)
            }

            // リトライ判定
            if attempt < maxAttempts && retryPolicy.shouldRetry(statusCode: statusCode, attempt: attempt) {
                let retryAfter = Self.parseRetryAfter(from: httpResponse)
                let delay = retryPolicy.delay(for: attempt, retryAfter: retryAfter)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                continue
            }

            // エラー処理
            logContinuation.yield(.httpError(endpoint: endpoint, statusCode: statusCode, data: data))
            emitEvent(for: statusCode, endpoint: endpoint, data: data, httpResponse: httpResponse)

            // カスタムエラーデコード試行
            let responseHeaders = Self.extractHeaders(from: httpResponse)
            if let customError = decodeError(statusCode, data, responseHeaders, decoder) {
                throw customError
            }

            throw mapToAPIError(statusCode: statusCode, data: data)
        }

        fatalError("Unreachable: retry loop should always return or throw")
    }

    private func sendRequest(
        _ endpoint: APIEndpoint,
        authScheme: AuthScheme,
        groupHeaders: [String: String],
        endpointHeaders: [String: String]
    ) async throws -> (Data, HTTPURLResponse) {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: true) else {
            throw APIError.invalidURL
        }

        // AuthScheme.queryParam の場合、認証トークンをクエリに追加
        if case .queryParam(let name) = authScheme,
           let token = try await authTokenProvider?.getToken() {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: name, value: token))
            components.queryItems = items
        }

        if let queryItems = endpoint.queryItems {
            var items = components.queryItems ?? []
            items.append(contentsOf: queryItems)
            components.queryItems = items
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.timeoutInterval = timeout

        // 1. デフォルトヘッダー
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // 2. ユーザー指定のデフォルトヘッダー
        for (key, value) in defaultHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // 3. 認証（AuthScheme に基づく）
        switch authScheme {
        case .none:
            break
        case .bearer:
            if let token = try await authTokenProvider?.getToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        case .apiKey(let headerName):
            if let token = try await authTokenProvider?.getToken() {
                request.setValue(token, forHTTPHeaderField: headerName)
            }
        case .queryParam:
            break // クエリパラメータは上で処理済み
        }

        // 4. グループ共通ヘッダー
        for (key, value) in groupHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // 5. エンドポイント固有ヘッダー
        for (key, value) in endpointHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // 6. APIEndpoint のヘッダー（後方互換）
        endpoint.headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        return (data, httpResponse)
    }

    private func emitEvent(for statusCode: Int, endpoint: APIEndpoint, data: Data, httpResponse: HTTPURLResponse) {
        switch statusCode {
        case 401:
            eventContinuation.yield(.unauthorized(endpoint: endpoint, data: data))
        case 403:
            eventContinuation.yield(.forbidden(endpoint: endpoint, data: data))
        case 429:
            let retryAfter = Self.parseRetryAfter(from: httpResponse)
            eventContinuation.yield(.rateLimited(endpoint: endpoint, retryAfter: retryAfter, data: data))
        case 503:
            eventContinuation.yield(.serviceUnavailable(endpoint: endpoint, data: data))
        case 500...599:
            eventContinuation.yield(.serverError(statusCode: statusCode, endpoint: endpoint, data: data))
        default:
            break
        }
    }

    private func mapToAPIError(statusCode: Int, data: Data) -> APIError {
        switch statusCode {
        case 401, 403:
            return .unauthorized
        default:
            return .httpError(statusCode: statusCode, data: data)
        }
    }

    private static func extractHeaders(from response: HTTPURLResponse) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let keyStr = key as? String, let valStr = value as? String {
                result[keyStr] = valStr
            }
        }
        return result
    }

    static func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let retryAfterValue = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }

        if let seconds = TimeInterval(retryAfterValue) {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = formatter.date(from: retryAfterValue) {
            let interval = date.timeIntervalSinceNow
            return interval > 0 ? interval : nil
        }

        return nil
    }

    static func defaultDateEncodingStrategy() -> JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let dateString = formatter.string(from: date)
            var container = encoder.singleValueContainer()
            try container.encode(dateString)
        }
    }

    static func defaultDateDecodingStrategy() -> JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            let fallbackFormatter = DateFormatter()
            fallbackFormatter.dateFormat = "yyyy-MM-dd"
            fallbackFormatter.calendar = Calendar(identifier: .iso8601)
            fallbackFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = fallbackFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateString)"
            )
        }
    }
}
