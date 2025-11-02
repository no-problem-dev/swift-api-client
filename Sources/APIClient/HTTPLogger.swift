import Foundation

/// HTTP通信のログ出力を抽象化するプロトコル
///
/// APIClientの実装から、ロギング処理の責務を分離するためのインターフェース。
/// 環境ごとに異なるロガー実装（Console、OSLog、Analyticsなど）を差し替え可能にします。
public protocol HTTPLogger: Sendable {
    /// 成功したリクエストをログ出力
    /// - Parameters:
    ///   - endpoint: リクエストしたエンドポイント
    ///   - statusCode: HTTPステータスコード
    ///   - responseData: レスポンスボディのデータ
    func logSuccess(endpoint: APIEndpoint, statusCode: Int, responseData: Data)

    /// HTTPエラーをログ出力
    /// - Parameters:
    ///   - statusCode: HTTPステータスコード
    ///   - endpoint: リクエストしたエンドポイント
    ///   - data: エラーレスポンスのデータ
    func logHTTPError(statusCode: Int, endpoint: APIEndpoint, data: Data)

    /// デコードエラーをログ出力
    /// - Parameters:
    ///   - error: デコードエラー
    ///   - endpoint: リクエストしたエンドポイント
    ///   - responseData: デコードに失敗したレスポンスデータ
    ///   - targetType: デコード対象の型
    func logDecodingError<T>(
        error: Error,
        endpoint: APIEndpoint,
        responseData: Data,
        targetType: T.Type
    )
}

/// コンソール出力を行うHTTPLoggerの実装
///
/// printを使用してコンソールにログを出力します。
/// デバッグ環境で詳細なリクエスト/レスポンス情報を確認するために使用します。
public struct ConsoleHTTPLogger: HTTPLogger {
    public init() {}

    public func logSuccess(endpoint: APIEndpoint, statusCode: Int, responseData: Data) {
        var output = """
        ✅ ========== API REQUEST SUCCESS ==========
        📍 Endpoint: \(endpoint.method.rawValue) \(endpoint.path)
        ✅ Status Code: \(statusCode)

        """

        if responseData.count < 10000 {
            output += "📄 Response Data:\n"
            output += formatJSON(data: responseData)
        } else {
            output += "📄 Response Data: \(responseData.count) bytes (too large to display)"
        }

        output += "\n✅ ========== END REQUEST SUCCESS ==========\n"
        print(output)
    }

    public func logHTTPError(statusCode: Int, endpoint: APIEndpoint, data: Data) {
        var output = """
        ❌ ========== HTTP ERROR ==========
        📍 Endpoint: \(endpoint.method.rawValue) \(endpoint.path)
        🚫 Status Code: \(statusCode)
        📄 Error Response:

        """
        output += formatJSON(data: data)
        output += "\n❌ ========== END HTTP ERROR ==========\n"
        print(output)
    }

    public func logDecodingError<T>(
        error: Error,
        endpoint: APIEndpoint,
        responseData: Data,
        targetType: T.Type
    ) {
        var output = """
        ❌ ========== DECODE ERROR ==========
        📍 Endpoint: \(endpoint.method.rawValue) \(endpoint.path)
        🎯 Target Type: \(String(describing: targetType))
        ❗ Error: \(error)

        """

        if let decodingError = error as? DecodingError {
            output += "🔍 Decoding Error Details:\n"
            output += formatDecodingErrorDetails(decodingError)
            output += "\n"
        }

        output += "📄 Response Data:\n"
        output += formatJSON(data: responseData)
        output += "\n❌ ========== END DECODE ERROR ==========\n"
        print(output)
    }

    // MARK: - Private Helpers

    private func formatJSON(data: Data) -> String {
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

    private func formatDecodingErrorDetails(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            return """
              - Type Mismatch: expected \(type), at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))
              - Debug Description: \(context.debugDescription)
            """
        case .valueNotFound(let type, let context):
            return """
              - Value Not Found: type \(type), at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))
              - Debug Description: \(context.debugDescription)
            """
        case .keyNotFound(let key, let context):
            return """
              - Key Not Found: '\(key.stringValue)', at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))
              - Debug Description: \(context.debugDescription)
            """
        case .dataCorrupted(let context):
            return """
              - Data Corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))
              - Debug Description: \(context.debugDescription)
            """
        @unknown default:
            return "  - Unknown decoding error"
        }
    }
}

/// ログ出力を行わないHTTPLoggerの実装
///
/// 本番環境やテスト環境で、ログ出力を無効化したい場合に使用します。
public struct SilentHTTPLogger: HTTPLogger {
    public init() {}

    public func logSuccess(endpoint: APIEndpoint, statusCode: Int, responseData: Data) {}
    public func logHTTPError(statusCode: Int, endpoint: APIEndpoint, data: Data) {}
    public func logDecodingError<T>(
        error: Error,
        endpoint: APIEndpoint,
        responseData: Data,
        targetType: T.Type
    ) {}
}
