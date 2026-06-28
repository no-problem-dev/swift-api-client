import Foundation

/// 認証トークンを非同期に提供するプロバイダー。
///
/// `APIClientImpl` に渡すと、Bearer / apiKey / queryParam 認証スキームで
/// トークンが自動挿入される。Keychain や OAuth ライブラリのラッパーとして実装する。
///
/// スコープ分岐が必要な場合は ``ScopedAuthTokenProvider`` を使う。
public protocol AuthTokenProvider: Sendable {
    /// 認証トークンを取得する。`nil` を返すと認証なしで送信し、throw すると取得失敗として扱う。
    func fetchToken() async throws -> String?
}

/// スコープ対応の認証トークンプロバイダー。
///
/// OAuth のように「エンドポイントごとに必要な権限スコープが異なる」API 向け。
/// `APIClientImpl` は契約 (`APIContract.requiredScopes`) を読み取り、プロバイダが
/// この型に適合していれば `fetchToken(scopes:)` を呼ぶ。
///
/// 注意: OAuth ではアクセストークンは単一であり、スコープは「認可時に付与済みか」を
/// 表す。`scopes` は別トークンの選択ではなく、付与済みスコープの事前検証
/// （インクリメンタル認可の UX 駆動）に使うのが一般的。
public protocol ScopedAuthTokenProvider: AuthTokenProvider {
    /// 指定スコープに対するトークンを取得する。`scopes` は契約の `requiredScopes` が渡され、付与済みスコープの事前検証に使う。
    func fetchToken(scopes: [String]) async throws -> String?
}

extension ScopedAuthTokenProvider {
    /// スコープ非対応の呼び出しは空スコープへ委譲する。
    public func fetchToken() async throws -> String? {
        try await fetchToken(scopes: [])
    }
}
