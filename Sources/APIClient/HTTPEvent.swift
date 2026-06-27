import Foundation

/// アプリ全体で横断的に処理すべき HTTP イベント。
///
/// `APIClientImpl.events` を `AsyncStream` で受信し、ログアウト・メンテ画面遷移・
/// レート制限 UI などをイベント駆動で実装するために使う。
///
/// ```swift
/// Task {
///     for await event in client.events {
///         switch event {
///         case .unauthorized: await authManager.handleLogout()
///         case .rateLimited(_, let retry, _): scheduleRetry(after: retry)
///         default: break
///         }
///     }
/// }
/// ```
public enum HTTPEvent: Sendable {
    case unauthorized(endpoint: APIEndpoint, data: Data)
    case forbidden(endpoint: APIEndpoint, data: Data)
    case rateLimited(endpoint: APIEndpoint, retryAfter: TimeInterval?, data: Data)
    case serviceUnavailable(endpoint: APIEndpoint, data: Data)
    case serverError(statusCode: Int, endpoint: APIEndpoint, data: Data)
}
