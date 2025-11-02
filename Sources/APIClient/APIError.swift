import Foundation

/// APIエラー
public enum APIError: LocalizedError {
    case networkError(Error)
    case decodingError(Error)
    case invalidURL
    case invalidResponse
    case unauthorized
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
