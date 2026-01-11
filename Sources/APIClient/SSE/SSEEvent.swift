import Foundation

/// Server-Sent Events (SSE) event
///
/// Represents a single event from an SSE stream following the WHATWG specification.
/// https://html.spec.whatwg.org/multipage/server-sent-events.html
public struct SSEEvent: Sendable, Equatable, Hashable {
    /// Event data (optional)
    public let data: String?

    /// Event type (optional, defaults to "message")
    public let event: String?

    /// Event ID for reconnection (optional)
    public let id: String?

    /// Reconnection time in milliseconds (optional)
    public let retry: Int?

    public init(
        data: String? = nil,
        event: String? = nil,
        id: String? = nil,
        retry: Int? = nil
    ) {
        self.data = data
        self.event = event
        self.id = id
        self.retry = retry
    }
}

// MARK: - JSON Decoding

extension SSEEvent {
    /// Decode data field as JSON
    public func decodeData<T: Decodable>(
        _ type: T.Type,
        decoder: JSONDecoder = .init()
    ) throws -> T {
        guard let data = data?.data(using: .utf8) else {
            throw SSEError.noData
        }
        return try decoder.decode(type, from: data)
    }

    /// Decode data field as JSON with ISO8601 date strategy
    public func decodeDataWithISO8601<T: Decodable>(_ type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decodeData(type, decoder: decoder)
    }
}

// MARK: - SSE Errors

public enum SSEError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, data: Data?)
    case noData
    case decodingError(Error)
    case connectionClosed
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, _):
            return "HTTP error: \(statusCode)"
        case .noData:
            return "No data in event"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .connectionClosed:
            return "Connection closed"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
