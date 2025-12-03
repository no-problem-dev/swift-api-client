import Foundation

/// アプリケーション全体で処理すべき重要なHTTPイベント
///
/// これらのイベントは、個別のリクエスト箇所ではなく、
/// アプリケーション全体で一元的に処理すべき重要なHTTPレスポンスを表します。
///
/// ## 使用例
/// ```swift
/// Task {
///     for await event in client.events {
///         switch event {
///         case .unauthorized:
///             await authManager.handleLogout()
///         case .serviceUnavailable:
///             await router.showMaintenanceScreen()
///         default:
///             break
///         }
///     }
/// }
/// ```
///
/// - Note: イベントはエラーのthrowと同時に発行されます。
///   エラーハンドリングは従来通り各呼び出し箇所で行い、
///   このイベントストリームはグローバルな対応（ログアウト、メンテナンス画面等）に使用します。
public enum HTTPEvent: Sendable {
    /// 認証エラー（401 Unauthorized）
    ///
    /// トークンの期限切れやログアウトが必要な状態を示します。
    /// - Parameters:
    ///   - endpoint: エラーが発生したエンドポイント
    ///   - data: サーバーからのレスポンスデータ
    case unauthorized(endpoint: APIEndpoint, data: Data)

    /// アクセス禁止（403 Forbidden）
    ///
    /// 認証済みだがリソースへのアクセス権限がない状態を示します。
    /// - Parameters:
    ///   - endpoint: エラーが発生したエンドポイント
    ///   - data: サーバーからのレスポンスデータ
    case forbidden(endpoint: APIEndpoint, data: Data)

    /// レート制限（429 Too Many Requests）
    ///
    /// リクエスト数が制限を超えた状態を示します。
    /// - Parameters:
    ///   - endpoint: エラーが発生したエンドポイント
    ///   - retryAfter: 再試行までの待機時間（秒）。Retry-Afterヘッダーから取得。
    ///   - data: サーバーからのレスポンスデータ
    case rateLimited(endpoint: APIEndpoint, retryAfter: TimeInterval?, data: Data)

    /// サービス利用不可（503 Service Unavailable）
    ///
    /// サーバーがメンテナンス中または一時的に利用できない状態を示します。
    /// - Parameters:
    ///   - endpoint: エラーが発生したエンドポイント
    ///   - data: サーバーからのレスポンスデータ
    case serviceUnavailable(endpoint: APIEndpoint, data: Data)

    /// サーバーエラー（500-599、503を除く）
    ///
    /// サーバー側で予期しないエラーが発生した状態を示します。
    /// - Parameters:
    ///   - statusCode: HTTPステータスコード
    ///   - endpoint: エラーが発生したエンドポイント
    ///   - data: サーバーからのレスポンスデータ
    case serverError(statusCode: Int, endpoint: APIEndpoint, data: Data)
}
