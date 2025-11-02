import Foundation

/// 認証トークンを提供するプロトコル
public protocol AuthTokenProvider: Sendable {
    func getToken() async throws -> String?
}
