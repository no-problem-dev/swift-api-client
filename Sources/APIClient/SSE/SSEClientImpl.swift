import APIContract
import Foundation

// SSEClientImpl uses URLSession.AsyncBytes (session.bytes(for:)), which is
// only available on Darwin platforms. On Linux (e.g. Cloud Run server builds),
// this type is conditionally compiled out — server code uses HTTPStreamingClient
// from swift-llm-cloud instead.
#if canImport(Darwin)

/// Server-Sent Events (SSE) client implementation
///
/// Connects to SSE endpoints and streams events as they arrive.
/// Follows the WHATWG SSE specification.
///
/// ## Implementation Notes
/// Uses `URLSession.AsyncBytes.lines` instead of raw bytes to avoid
/// URLSession's 512-byte buffering behavior. This ensures SSE events
/// are delivered immediately as each line is received.
public struct SSEClientImpl: SSEClient, Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let authTokenProvider: (any AuthTokenProvider)?
    private let defaultHeaders: [String: String]
    private let encoder: JSONEncoder

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        authTokenProvider: (any AuthTokenProvider)? = nil,
        defaultHeaders: [String: String] = [:]
    ) {
        self.baseURL = baseURL
        self.session = session
        self.authTokenProvider = authTokenProvider
        self.defaultHeaders = defaultHeaders

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    public func connect(
        path: String,
        queryItems: [URLQueryItem]?
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        connect(path: path, method: "GET", body: nil as EmptySSEBody?, queryItems: queryItems)
    }

    public func connect<Body: Encodable & Sendable>(
        path: String,
        method: String,
        body: Body?,
        queryItems: [URLQueryItem]?
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        let bodyData: Data? = body.flatMap { try? encoder.encode($0) }
        return connectWithData(path: path, method: method, bodyData: bodyData, queryItems: queryItems)
    }

    /// 生のDataを使用したSSE接続
    ///
    /// StreamingAPIContract等、既にエンコード済みのボディを使用する場合に使用。
    public func connectWithData(
        path: String,
        method: String,
        bodyData: Data?,
        queryItems: [URLQueryItem]?
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        connectWithData(
            path: path,
            method: method,
            bodyData: bodyData,
            queryItems: queryItems,
            authScheme: .bearer,
            groupHeaders: [:],
            endpointHeaders: [:]
        )
    }

    /// AuthScheme・ヘッダー付きSSE接続（StreamingAPIContract用）
    internal func connectWithData(
        path: String,
        method: String,
        bodyData: Data?,
        queryItems: [URLQueryItem]?,
        authScheme: AuthScheme,
        groupHeaders: [String: String],
        endpointHeaders: [String: String]
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        // Capture values before creating the stream
        let url = baseURL.appendingPathComponent(path)
        let session = self.session
        let authTokenProvider = self.authTokenProvider
        let defaultHeaders = self.defaultHeaders

        return AsyncThrowingStream { continuation in
            Task { @Sendable in
                do {
                    // Build URL with query items
                    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
                        throw SSEError.invalidURL
                    }

                    // AuthScheme.queryParam の場合、認証トークンをクエリに追加
                    if case .queryParam(let name) = authScheme,
                       let token = try await authTokenProvider?.getToken() {
                        var items = components.queryItems ?? []
                        items.append(URLQueryItem(name: name, value: token))
                        components.queryItems = items
                    }

                    if let queryItems {
                        var items = components.queryItems ?? []
                        items.append(contentsOf: queryItems)
                        components.queryItems = items
                    }

                    guard let requestURL = components.url else {
                        throw SSEError.invalidURL
                    }

                    // Build request
                    var request = URLRequest(url: requestURL)
                    request.httpMethod = method
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

                    // Add default headers
                    for (key, value) in defaultHeaders {
                        request.setValue(value, forHTTPHeaderField: key)
                    }

                    // Auth based on AuthScheme
                    switch authScheme {
                    case .none:
                        break
                    case .bearer:
                        if let token = try await authTokenProvider?.getToken() {
                            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        }
                    case .apiKey(let headerName):
                        if let token = try await authTokenProvider?.getToken() {
                            request.setValue(token, forHTTPHeaderField: headerName)
                        }
                    case .queryParam:
                        break // Already handled above
                    }

                    // Group common headers
                    for (key, value) in groupHeaders {
                        request.setValue(value, forHTTPHeaderField: key)
                    }

                    // Endpoint-specific headers
                    for (key, value) in endpointHeaders {
                        request.setValue(value, forHTTPHeaderField: key)
                    }

                    // Add body if present
                    if let bodyData {
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.httpBody = bodyData
                    }

                    // Start streaming
                    print("🌐 SSEClient: Starting request to \(requestURL)")
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("❌ SSEClient: Invalid response type")
                        throw SSEError.invalidResponse
                    }

                    print("🌐 SSEClient: Response status: \(httpResponse.statusCode)")

                    guard (200...299).contains(httpResponse.statusCode) else {
                        print("❌ SSEClient: HTTP error \(httpResponse.statusCode)")
                        throw SSEError.httpError(statusCode: httpResponse.statusCode, data: nil)
                    }

                    // Parse SSE events using lines
                    // Note: bytes.lines skips empty lines, so we detect event boundaries
                    // by checking for new "event:" or "data:" fields when we already have data
                    var currentEvent: String?
                    var currentData: String?
                    var eventCount = 0
                    var lineCount = 0

                    print("🌐 SSEClient: Starting to read line stream...")

                    for try await line in bytes.lines {
                        lineCount += 1
                        print("🌐 SSEClient: Line #\(lineCount): \(line.prefix(80))...")

                        // Skip comment lines
                        if line.hasPrefix(":") {
                            continue
                        }

                        // Parse field
                        let parts = line.split(separator: ":", maxSplits: 1)
                        guard let field = parts.first else { continue }
                        let value = parts.count > 1
                            ? String(parts[1]).trimmingCharacters(in: .init(charactersIn: " "))
                            : ""

                        let fieldName = String(field)

                        switch fieldName {
                        case "event":
                            // If we already have data, emit the previous event first
                            if let data = currentData {
                                let event = SSEEvent(data: data, event: currentEvent)
                                eventCount += 1
                                print("🌐 SSEClient: Emitting event #\(eventCount): \(event.event ?? "no-event")")
                                continuation.yield(event)
                            }
                            // Start new event
                            currentEvent = value
                            currentData = nil

                        case "data":
                            // If we have an event type but encounter new data, check if this
                            // is a continuation or a new event
                            if currentData != nil && currentEvent != nil {
                                // We have complete previous event, emit it
                                let event = SSEEvent(data: currentData, event: currentEvent)
                                eventCount += 1
                                print("🌐 SSEClient: Emitting event #\(eventCount): \(event.event ?? "no-event")")
                                continuation.yield(event)
                                // Reset for new event
                                currentEvent = nil
                                currentData = value
                            } else if currentData == nil {
                                currentData = value
                            } else {
                                // Multiple data fields - concatenate with newline per spec
                                currentData! += "\n" + value
                            }

                        case "id":
                            // Handle id field if needed
                            break

                        case "retry":
                            // Handle retry field if needed
                            break

                        default:
                            break
                        }
                    }

                    // Emit any remaining event
                    if let data = currentData {
                        let event = SSEEvent(data: data, event: currentEvent)
                        eventCount += 1
                        print("🌐 SSEClient: Emitting final event #\(eventCount): \(event.event ?? "no-event")")
                        continuation.yield(event)
                    }

                    print("🌐 SSEClient: Stream finished, total lines: \(lineCount), total events: \(eventCount)")
                    continuation.finish()
                } catch {
                    print("❌ SSEClient: Error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Internal (for testing)

    /// Parse SSE event from raw event string
    /// Exposed as internal for unit testing
    internal static func parseEvent(from string: String) -> SSEEvent? {
        var data: String?
        var event: String?
        var id: String?
        var retry: Int?

        let lines = string.components(separatedBy: "\n")

        for line in lines {
            if line.isEmpty { continue }

            // Comment lines start with ":"
            if line.hasPrefix(":") {
                continue
            }

            let parts = line.split(separator: ":", maxSplits: 1)
            guard let field = parts.first else { continue }

            // Value is everything after the colon, with leading space trimmed
            let value = parts.count > 1
                ? String(parts[1]).trimmingCharacters(in: .init(charactersIn: " "))
                : ""

            switch String(field) {
            case "data":
                // Multiple data fields are concatenated with newlines
                if data == nil {
                    data = value
                } else {
                    data! += "\n" + value
                }
            case "event":
                event = value
            case "id":
                id = value
            case "retry":
                retry = Int(value)
            default:
                // Unknown fields are ignored per spec
                break
            }
        }

        // Return nil if no meaningful content
        guard data != nil || event != nil || id != nil || retry != nil else {
            return nil
        }

        return SSEEvent(data: data, event: event, id: id, retry: retry)
    }
}

#endif // canImport(Darwin)

// MARK: - Helper Types

/// Empty body type for SSE requests
public struct EmptySSEBody: Encodable, Sendable {}
