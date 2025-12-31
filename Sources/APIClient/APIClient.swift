@_exported import APIContract
import Foundation

/// HTTPベースのAPI通信を抽象化するクライアントインターフェース
///
/// このプロトコルは、RESTful APIとの通信における以下の責務を定義します：
/// - エンドポイントへのHTTPリクエスト送信
/// - レスポンスのデコードと型安全な取得
/// - エラーハンドリングの統一
///
/// ## 使用例
/// ```swift
/// let client: APIClient = APIClientImpl(baseURL: URL(string: "https://api.example.com")!)
/// let user: User = try await client.request(.get("/users/123"))
/// ```
///
/// - Note: このプロトコルに準拠する実装は`Sendable`である必要があります
public protocol APIClient: APIExecutor {
    /// オブジェクトをJSONデータにエンコードする
    /// APIClientの日付エンコーディング戦略が適用される
    /// - Parameter value: エンコードする値
    /// - Returns: エンコードされたJSONデータ
    /// - Throws: エンコードエラー
    func encode<T: Encodable>(_ value: T) throws -> Data

    /// レスポンスをデコードしてジェネリック型として返すリクエストメソッド
    /// - Parameter endpoint: リクエスト情報を含むエンドポイント
    /// - Returns: デコードされたレスポンスオブジェクト
    /// - Throws: `APIError` - ネットワークエラー、デコードエラー、HTTPエラーなど
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T

    /// レスポンスボディを必要としないリクエストメソッド（DELETE等）
    /// - Parameter endpoint: リクエスト情報を含むエンドポイント
    /// - Throws: `APIError` - ネットワークエラー、HTTPエラーなど
    func request(_ endpoint: APIEndpoint) async throws

    /// 重要なHTTPイベント（401, 503等）のストリーム
    ///
    /// アプリケーション全体で処理すべき重要なHTTPレスポンス（認証エラー、サービス停止等）を
    /// 非同期ストリームとして提供します。
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
    /// - Important: このストリームは一度のみ購読可能（ユニキャスト設計）です。
    ///   DIコンテナ等で単一の購読Taskを立て、そこから各ハンドラーへ配信してください。
    /// - Note: イベントはエラーのthrowと同時に発行されます。
    ///   従来のエラーハンドリングと併用してください。
    var events: AsyncStream<HTTPEvent> { get }

    /// HTTPリクエスト/レスポンスのログストリーム
    ///
    /// すべてのHTTP通信のログ（成功、エラー、デコードエラー）を
    /// 非同期ストリームとして提供します。
    ///
    /// ## 使用例
    /// ```swift
    /// // デバッグ用コンソール出力
    /// Task {
    ///     for await log in client.logs {
    ///         switch log {
    ///         case .success(let endpoint, let statusCode, _):
    ///             print("✅ \(endpoint.path): \(statusCode)")
    ///         case .httpError(let endpoint, let statusCode, _):
    ///             print("❌ \(endpoint.path): \(statusCode)")
    ///         case .decodingError(let endpoint, let error, _, _):
    ///             print("⚠️ \(endpoint.path): \(error)")
    ///         }
    ///     }
    /// }
    ///
    /// // Analytics送信
    /// Task {
    ///     for await log in client.logs {
    ///         analytics.track(log)
    ///     }
    /// }
    /// ```
    ///
    /// - Important: このストリームは一度のみ購読可能（ユニキャスト設計）です。
    ///   DIコンテナ等で単一の購読Taskを立て、そこから各ハンドラーへ配信してください。
    var logs: AsyncStream<HTTPLog> { get }

    // NOTE: execute<E: APIContract>() メソッドは APIExecutor から継承
}
