import Foundation

/// アプリケーション全体で処理すべきHTTPイベント
public enum HTTPEvent: Sendable {
    case unauthorized(endpoint: APIEndpoint, data: Data)
    case forbidden(endpoint: APIEndpoint, data: Data)
    case rateLimited(endpoint: APIEndpoint, retryAfter: TimeInterval?, data: Data)
    case serviceUnavailable(endpoint: APIEndpoint, data: Data)
    case serverError(statusCode: Int, endpoint: APIEndpoint, data: Data)
}
