import Foundation

/// `APIClient` が送出するエラー型。
///
/// `executeWithResponse` / `execute` / `executeRaw` / `executeEventStream` が
/// 失敗した際にこの型のいずれかの case が throw される。
///
/// - Note: 認可エラー（401/403）は ``HTTPEvent/unauthorized`` / ``HTTPEvent/forbidden``
///   として `events` ストリームにも同時配信される。
public enum APIError: LocalizedError {
    /// 送受信レイヤー（URLSession 等）のエラー。`URLError` などをラップする。
    case networkError(Error)
    /// レスポンス JSON のデコードに失敗した。`DecodingError` をラップする。
    case decodingError(Error)
    /// URL の構築に失敗した（不正なパス・クエリパラメータ等）。
    case invalidURL
    /// 予期しないレスポンス形式。
    case invalidResponse
    /// 401 / 403 応答を受けた。
    case unauthorized
    /// 上記以外の非 2xx 応答。`data` にレスポンスボディが入る。
    case httpError(statusCode: Int, data: Data)

    public var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "ネットワークエラー: \(error.localizedDescription)"
        case .decodingError(let error):
            return "デコードエラー: \(error.localizedDescription)"
        case .invalidURL:
            return "無効なURLです"
        case .invalidResponse:
            return "無効なレスポンスです"
        case .unauthorized:
            return "認証が必要です"
        case .httpError(let statusCode, _):
            return "HTTPエラー: \(statusCode)"
        }
    }
}
