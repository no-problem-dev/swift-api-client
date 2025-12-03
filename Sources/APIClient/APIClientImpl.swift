import Foundation

/// APIクライアントの実装
public struct APIClientImpl: APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let authTokenProvider: AuthTokenProvider?
    private let timeout: TimeInterval
    private let defaultHeaders: [String: String]
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let eventSource = MulticastStreamSource<HTTPEvent>()
    private let logSource = MulticastStreamSource<HTTPLog>()

    /// 初期化
    ///
    /// - Parameters:
    ///   - baseURL: APIのベースURL
    ///   - session: URLSession
    ///   - authTokenProvider: 認証トークンプロバイダー
    ///   - timeout: タイムアウト時間（秒）
    ///   - defaultHeaders: デフォルトヘッダー
    ///   - keyDecodingStrategy: JSONキーのデコーディング戦略（デフォルト: .useDefaultKeys）
    ///   - dateEncodingStrategy: 日付のエンコーディング戦略（デフォルト: RFC3339）
    ///   - dateDecodingStrategy: 日付のデコーディング戦略（デフォルト: RFC3339フォールバック付き）
    public init(
        baseURL: URL,
        session: URLSession = .shared,
        authTokenProvider: AuthTokenProvider? = nil,
        timeout: TimeInterval = 60.0,
        defaultHeaders: [String: String] = [:],
        keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys,
        dateEncodingStrategy: JSONEncoder.DateEncodingStrategy? = nil,
        dateDecodingStrategy: JSONDecoder.DateDecodingStrategy? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.authTokenProvider = authTokenProvider
        self.timeout = timeout
        self.defaultHeaders = defaultHeaders

        // Encoder の設定
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = dateEncodingStrategy ?? Self.defaultDateEncodingStrategy()
        self.encoder = encoder

        // Decoder の設定
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = keyDecodingStrategy
        decoder.dateDecodingStrategy = dateDecodingStrategy ?? Self.defaultDateDecodingStrategy()
        self.decoder = decoder

    }

    public var events: AsyncStream<HTTPEvent> {
        get async {
            await eventSource.stream
        }
    }

    public var logs: AsyncStream<HTTPLog> {
        get async {
            await logSource.stream
        }
    }

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    public func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        let data = try await performRequest(endpoint)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            await logSource.emit(.decodingError(
                endpoint: endpoint,
                error: String(describing: error),
                data: data,
                targetType: String(describing: T.self)
            ))
            throw APIError.decodingError(error)
        }
    }

    public func request(_ endpoint: APIEndpoint) async throws {
        _ = try await performRequest(endpoint)
    }

    private func performRequest(_ endpoint: APIEndpoint) async throws -> Data {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: true) else {
            throw APIError.invalidURL
        }
        components.queryItems = endpoint.queryItems

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.timeoutInterval = timeout

        // デフォルトヘッダー
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Configuration のデフォルトヘッダーを適用
        defaultHeaders.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        // 認証トークンを追加
        if let token = try await authTokenProvider?.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // エンドポイント固有のカスタムヘッダー（上書き可能）
        endpoint.headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            let statusCode = httpResponse.statusCode

            switch statusCode {
            case 200...299:
                await logSource.emit(.success(endpoint: endpoint, statusCode: statusCode, data: data))
                return data
            case 400:
                await logSource.emit(.httpError(endpoint: endpoint, statusCode: statusCode, data: data))
                throw APIError.httpError(statusCode: statusCode, data: data)
            case 401:
                await logSource.emit(.httpError(endpoint: endpoint, statusCode: statusCode, data: data))
                await eventSource.emit(.unauthorized(endpoint: endpoint, data: data))
                throw APIError.unauthorized
            case 403:
                await logSource.emit(.httpError(endpoint: endpoint, statusCode: statusCode, data: data))
                await eventSource.emit(.forbidden(endpoint: endpoint, data: data))
                throw APIError.unauthorized
            case 404:
                await logSource.emit(.httpError(endpoint: endpoint, statusCode: statusCode, data: data))
                throw APIError.httpError(statusCode: statusCode, data: data)
            case 429:
                await logSource.emit(.httpError(endpoint: endpoint, statusCode: statusCode, data: data))
                let retryAfter = Self.parseRetryAfter(from: httpResponse)
                await eventSource.emit(.rateLimited(endpoint: endpoint, retryAfter: retryAfter, data: data))
                throw APIError.httpError(statusCode: statusCode, data: data)
            case 503:
                await logSource.emit(.httpError(endpoint: endpoint, statusCode: statusCode, data: data))
                await eventSource.emit(.serviceUnavailable(endpoint: endpoint, data: data))
                throw APIError.httpError(statusCode: statusCode, data: data)
            case 500...599:
                await logSource.emit(.httpError(endpoint: endpoint, statusCode: statusCode, data: data))
                await eventSource.emit(.serverError(statusCode: statusCode, endpoint: endpoint, data: data))
                throw APIError.httpError(statusCode: statusCode, data: data)
            default:
                await logSource.emit(.httpError(endpoint: endpoint, statusCode: statusCode, data: data))
                throw APIError.httpError(statusCode: statusCode, data: data)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }
}

/// 空のレスポンス型
public struct EmptyResponse: Sendable, Codable {
    public init() {}
}

// MARK: - HTTP Header Parsing
extension APIClientImpl {
    /// Retry-Afterヘッダーから待機時間を解析
    static func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let retryAfterValue = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }

        // 秒数として解析を試みる
        if let seconds = TimeInterval(retryAfterValue) {
            return seconds
        }

        // HTTP-date形式として解析を試みる
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = formatter.date(from: retryAfterValue) {
            let interval = date.timeIntervalSinceNow
            return interval > 0 ? interval : nil
        }

        return nil
    }
}

// MARK: - Date Encoding/Decoding Strategies
extension APIClientImpl {
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
                debugDescription: "Invalid date format: \(dateString). Expected RFC3339 (e.g., '2024-01-15T10:30:00Z') or date-only (e.g., '2024-01-15')"
            )
        }
    }
}
