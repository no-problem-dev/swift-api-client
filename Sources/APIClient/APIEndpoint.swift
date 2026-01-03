import APIContract
import Foundation

/// APIエンドポイント
public struct APIEndpoint: Sendable {
    public let path: String
    public let method: APIMethod
    public let headers: [String: String]?
    public let body: Data?
    public let queryItems: [URLQueryItem]?

    public init(
        path: String,
        method: APIMethod = .get,
        headers: [String: String]? = nil,
        body: Data? = nil,
        queryItems: [URLQueryItem]? = nil
    ) {
        self.path = path
        self.method = method
        self.headers = headers
        self.body = body
        self.queryItems = queryItems
    }
}
