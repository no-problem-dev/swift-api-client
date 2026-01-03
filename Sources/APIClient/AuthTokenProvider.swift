import Foundation

/// 認証トークンプロバイダー
public protocol AuthTokenProvider: Sendable {
    func getToken() async throws -> String?
}
