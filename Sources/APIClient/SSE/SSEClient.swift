import Foundation

/// Server-Sent Events (SSE) client protocol
public protocol SSEClient: Sendable {
    /// Connect to SSE endpoint with GET method
    func connect(
        path: String,
        queryItems: [URLQueryItem]?
    ) -> AsyncThrowingStream<SSEEvent, Error>

    /// Connect to SSE endpoint with POST method and body
    func connect<Body: Encodable & Sendable>(
        path: String,
        method: String,
        body: Body?,
        queryItems: [URLQueryItem]?
    ) -> AsyncThrowingStream<SSEEvent, Error>
}

// MARK: - Default implementations

extension SSEClient {
    /// Connect with GET method (no body)
    public func connect(path: String) -> AsyncThrowingStream<SSEEvent, Error> {
        connect(path: path, queryItems: nil)
    }

    /// Connect with POST method
    public func post<Body: Encodable & Sendable>(
        path: String,
        body: Body
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        connect(path: path, method: "POST", body: body, queryItems: nil)
    }

    /// Connect with POST method and query items
    public func post<Body: Encodable & Sendable>(
        path: String,
        body: Body,
        queryItems: [URLQueryItem]?
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        connect(path: path, method: "POST", body: body, queryItems: queryItems)
    }
}
