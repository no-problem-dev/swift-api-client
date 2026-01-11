import Foundation
import APIContract

// MARK: - StreamingAPIExecutable Implementation

extension SSEClientImpl: StreamingAPIExecutable {
    /// StreamingAPIContractを使用してSSEストリームを開始
    ///
    /// 型安全なストリーミングAPI実行。契約で定義されたEvent型に自動デコードされる。
    ///
    /// ## 使用例
    /// ```swift
    /// let client = SSEClientImpl(baseURL: baseURL)
    /// let stream = client.execute(SearchAPI.StreamSearch(query: "ramen"))
    /// for try await event in stream {
    ///     // event は SearchEvent 型
    /// }
    /// ```
    public func execute<E: StreamingAPIContract>(
        _ contract: E
    ) -> AsyncThrowingStream<E.Event, Error> where E.Input == E, E: APIInput {
        // 契約からリクエスト情報を構築
        let path = E.resolvePath(with: contract)
        let method = E.method.rawValue
        let queryItems: [URLQueryItem]?

        if let params = contract.queryParameters, !params.isEmpty {
            queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        } else {
            queryItems = nil
        }

        // エンコーダーとボディを準備
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bodyData: Data? = try? contract.encodeBody(using: encoder)

        // デコーダーを準備
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // SSEEventストリームを取得（connectWithDataを使用して二重エンコードを回避）
        let sseStream = connectWithData(
            path: path,
            method: method,
            bodyData: bodyData,
            queryItems: queryItems
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await sseEvent in sseStream {
                        // SSEEventのdataをEvent型にデコード
                        guard let data = sseEvent.data,
                              let eventData = data.data(using: .utf8) else {
                            continue
                        }

                        do {
                            let event = try decoder.decode(E.Event.self, from: eventData)
                            continuation.yield(event)
                        } catch {
                            // デコードエラーはログして続行
                            print("⚠️ SSEClient: Failed to decode event: \(error)")
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
