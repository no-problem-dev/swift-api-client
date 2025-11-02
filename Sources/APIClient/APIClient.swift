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
public protocol APIClient: Sendable {
    /// レスポンスをデコードしてジェネリック型として返すリクエストメソッド
    /// - Parameter endpoint: リクエスト情報を含むエンドポイント
    /// - Returns: デコードされたレスポンスオブジェクト
    /// - Throws: `APIError` - ネットワークエラー、デコードエラー、HTTPエラーなど
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T

    /// レスポンスボディを必要としないリクエストメソッド（DELETE等）
    /// - Parameter endpoint: リクエスト情報を含むエンドポイント
    /// - Throws: `APIError` - ネットワークエラー、HTTPエラーなど
    func request(_ endpoint: APIEndpoint) async throws
}
