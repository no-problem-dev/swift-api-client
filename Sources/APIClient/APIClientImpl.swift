import Foundation

/// APIクライアントの実装
public struct APIClientImpl: APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let authTokenProvider: AuthTokenProvider?
    private let timeout: TimeInterval
    private let defaultHeaders: [String: String]
    private let logger: HTTPLogger?

    /// 初期化
    ///
    /// - Parameters:
    ///   - baseURL: APIのベースURL
    ///   - session: URLSession
    ///   - authTokenProvider: 認証トークンプロバイダー
    ///   - enableDebugLog: デバッグログの有効化
    ///   - timeout: タイムアウト時間（秒）
    ///   - defaultHeaders: デフォルトヘッダー
    public init(
        baseURL: URL,
        session: URLSession = .shared,
        authTokenProvider: AuthTokenProvider? = nil,
        enableDebugLog: Bool = false,
        timeout: TimeInterval = 60.0,
        defaultHeaders: [String: String] = [:]
    ) {
        self.baseURL = baseURL
        self.session = session
        self.authTokenProvider = authTokenProvider
        self.timeout = timeout
        self.defaultHeaders = defaultHeaders
        self.logger = enableDebugLog ? ConsoleHTTPLogger() : nil
    }

    public func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        let data = try await performRequest(endpoint)

        let decoder = JSONDecoder()
        // カスタムISO8601日付フォーマット対応
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // ミリ秒付きISO8601フォーマット
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
            formatter.calendar = Calendar(identifier: .iso8601)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.locale = Locale(identifier: "en_US_POSIX")

            if let date = formatter.date(from: dateString) {
                return date
            }

            // ミリ秒なしISO8601フォーマット
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
            if let date = formatter.date(from: dateString) {
                return date
            }

            // 標準ISO8601フォーマット
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateString)"
            )
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logger?.logDecodingError(
                error: error,
                endpoint: endpoint,
                responseData: data,
                targetType: T.self
            )
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

            switch httpResponse.statusCode {
            case 200...299:
                logger?.logSuccess(endpoint: endpoint, statusCode: httpResponse.statusCode, responseData: data)
                return data
            case 400:
                logger?.logHTTPError(statusCode: 400, endpoint: endpoint, data: data)
                throw APIError.httpError(statusCode: 400, data: data)
            case 401:
                logger?.logHTTPError(statusCode: 401, endpoint: endpoint, data: data)
                throw APIError.unauthorized
            case 403:
                logger?.logHTTPError(statusCode: 403, endpoint: endpoint, data: data)
                throw APIError.unauthorized
            case 404:
                logger?.logHTTPError(statusCode: 404, endpoint: endpoint, data: data)
                throw APIError.httpError(statusCode: 404, data: data)
            case 429:
                logger?.logHTTPError(statusCode: 429, endpoint: endpoint, data: data)
                throw APIError.httpError(statusCode: 429, data: data)
            case 500...599:
                logger?.logHTTPError(statusCode: httpResponse.statusCode, endpoint: endpoint, data: data)
                throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
            default:
                logger?.logHTTPError(statusCode: httpResponse.statusCode, endpoint: endpoint, data: data)
                throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
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
