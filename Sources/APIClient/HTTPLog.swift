import Foundation

/// HTTPリクエスト/レスポンスのログエントリ
///
/// APIクライアントの通信状況を監視するためのログ情報を提供します。
/// デバッグ、Analytics、モニタリングなど様々な用途に使用できます。
///
/// ## 使用例
/// ```swift
/// // シンプルなコンソール出力（整形済み）
/// Task {
///     for await log in await client.logs {
///         print(log)  // CustomStringConvertibleによる整形出力
///     }
/// }
///
/// // カスタム処理
/// Task {
///     for await log in await client.logs {
///         switch log {
///         case .success(let endpoint, let statusCode, _):
///             analytics.trackSuccess(endpoint: endpoint.path, statusCode: statusCode)
///         case .httpError(let endpoint, let statusCode, _):
///             analytics.trackError(endpoint: endpoint.path, statusCode: statusCode)
///         case .decodingError(let endpoint, _, _, let targetType):
///             analytics.trackDecodingError(endpoint: endpoint.path, type: targetType)
///         }
///     }
/// }
/// ```
public enum HTTPLog: Sendable {
    /// リクエスト成功
    ///
    /// HTTPステータスコード 200-299 のレスポンスを受信した場合に発行されます。
    /// - Parameters:
    ///   - endpoint: リクエストしたエンドポイント
    ///   - statusCode: HTTPステータスコード
    ///   - data: レスポンスデータ
    case success(endpoint: APIEndpoint, statusCode: Int, data: Data)

    /// HTTPエラー
    ///
    /// HTTPステータスコード 400以上のレスポンスを受信した場合に発行されます。
    /// - Parameters:
    ///   - endpoint: リクエストしたエンドポイント
    ///   - statusCode: HTTPステータスコード
    ///   - data: レスポンスデータ（エラー詳細を含む場合があります）
    case httpError(endpoint: APIEndpoint, statusCode: Int, data: Data)

    /// デコードエラー
    ///
    /// レスポンスのJSONデコードに失敗した場合に発行されます。
    /// - Parameters:
    ///   - endpoint: リクエストしたエンドポイント
    ///   - error: デコードエラーの詳細
    ///   - data: デコードに失敗したレスポンスデータ
    ///   - targetType: デコード先の型名
    case decodingError(endpoint: APIEndpoint, error: String, data: Data, targetType: String)
}

// MARK: - CustomStringConvertible

extension HTTPLog: CustomStringConvertible {
    public var description: String {
        switch self {
        case .success(let endpoint, let statusCode, let data):
            return formatSuccess(endpoint: endpoint, statusCode: statusCode, data: data)
        case .httpError(let endpoint, let statusCode, let data):
            return formatHTTPError(endpoint: endpoint, statusCode: statusCode, data: data)
        case .decodingError(let endpoint, let error, let data, let targetType):
            return formatDecodingError(endpoint: endpoint, error: error, data: data, targetType: targetType)
        }
    }

    private func formatSuccess(endpoint: APIEndpoint, statusCode: Int, data: Data) -> String {
        var output = """
        ✅ ========== API REQUEST SUCCESS ==========
        📍 Endpoint: \(endpoint.method.rawValue) \(endpoint.path)
        ✅ Status Code: \(statusCode)

        """

        if data.count < 10000 {
            output += "📄 Response Data:\n"
            output += Self.formatJSON(data: data)
        } else {
            output += "📄 Response Data: \(data.count) bytes (too large to display)"
        }

        output += "\n✅ ========== END REQUEST SUCCESS =========="
        return output
    }

    private func formatHTTPError(endpoint: APIEndpoint, statusCode: Int, data: Data) -> String {
        var output = """
        ❌ ========== HTTP ERROR ==========
        📍 Endpoint: \(endpoint.method.rawValue) \(endpoint.path)
        🚫 Status Code: \(statusCode)
        📄 Error Response:

        """
        output += Self.formatJSON(data: data)
        output += "\n❌ ========== END HTTP ERROR =========="
        return output
    }

    private func formatDecodingError(endpoint: APIEndpoint, error: String, data: Data, targetType: String) -> String {
        var output = """
        ❌ ========== DECODE ERROR ==========
        📍 Endpoint: \(endpoint.method.rawValue) \(endpoint.path)
        🎯 Target Type: \(targetType)
        ❗ Error: \(error)

        📄 Response Data:

        """
        output += Self.formatJSON(data: data)
        output += "\n❌ ========== END DECODE ERROR =========="
        return output
    }

    private static func formatJSON(data: Data) -> String {
        if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
           let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        } else if let rawString = String(data: data, encoding: .utf8) {
            return "Raw data: \(rawString)"
        } else {
            return "Unable to convert data to string. Data size: \(data.count) bytes"
        }
    }
}
