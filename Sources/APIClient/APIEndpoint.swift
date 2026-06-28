import APIContract
import Foundation

/// HTTPイベント・ログのエンドポイント識別子。
///
/// `APIClientImpl` が ``HTTPEvent`` や ``HTTPLog`` を生成する際に、
/// どのエンドポイントで何が起きたかを伝えるための軽量な値型。
/// リクエスト構築には使われない（リクエストは ``APIContract`` 側が担う）。
public struct APIEndpoint: Sendable {
    /// パス文字列（例: `/v1/users`）
    public let path: String
    /// HTTP メソッド
    public let method: APIMethod

    /// エンドポイント識別子を生成する。
    ///
    /// - Parameters:
    ///   - path: パス文字列（例: `/v1/users`）。
    ///   - method: HTTP メソッド。省略時は `.get`。
    public init(
        path: String,
        method: APIMethod = .get
    ) {
        self.path = path
        self.method = method
    }
}
