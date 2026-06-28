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
    /// 401 応答。認証セッションの破棄・再認証フローのトリガーに使う。
    case unauthorized(endpoint: APIEndpoint, data: Data)
    /// 403 応答。権限不足による拒否。
    case forbidden(endpoint: APIEndpoint, data: Data)
    /// 429 応答。`retryAfter` は `Retry-After` ヘッダーから抽出した秒数（取得できない場合 `nil`）。
    case rateLimited(endpoint: APIEndpoint, retryAfter: TimeInterval?, data: Data)
    /// 503 応答。メンテナンス画面遷移などに使う。
    case serviceUnavailable(endpoint: APIEndpoint, data: Data)
    /// 500–599 のその他サーバーエラー。`statusCode` に実際のステータスコードが入る。
    case serverError(statusCode: Int, endpoint: APIEndpoint, data: Data)
}
