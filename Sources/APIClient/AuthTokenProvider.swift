import Foundation

/// 認証トークンプロバイダー
public protocol AuthTokenProvider: Sendable {
    func getToken() async throws -> String?
}

/// スコープ対応の認証トークンプロバイダー
///
/// OAuth のように「エンドポイントごとに必要な権限スコープが異なる」API 向け。
/// `APIClientImpl` は契約 (`APIContract.requiredScopes`) を読み取り、プロバイダが
/// この型に適合していれば `getToken(scopes:)` を呼ぶ。
///
/// 注意: OAuth ではアクセストークンは単一であり、スコープは「認可時に付与済みか」を
/// 表す。`scopes` は別トークンの選択ではなく、付与済みスコープの事前検証
/// （インクリメンタル認可の UX 駆動）に使うのが一般的。
public protocol ScopedAuthTokenProvider: AuthTokenProvider {
    func getToken(scopes: [String]) async throws -> String?
}

extension ScopedAuthTokenProvider {
    /// スコープ非対応の呼び出しは空スコープへ委譲する。
    public func getToken() async throws -> String? {
        try await getToken(scopes: [])
    }
}
