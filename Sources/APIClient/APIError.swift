import Foundation

/// What this package throws on its own behalf — which is not everything a call can throw.
///
/// Order your `catch` clauses accordingly:
///
/// 1. **Your group's error.** When an `APIContractGroup` implements `decodeError` and
///    returns a value for a response, that value is thrown *instead of* an `APIError`.
///    A `catch APIError.httpError` for a status your group maps will never run.
/// 2. **`APIError`.** Everything below.
/// 3. **Anything else.** Two paths bypass this type entirely: a throwing
///    ``AuthTokenProvider`` fails the call with its own error before the request is
///    sent, and ``APIClientImpl/execute(_:)`` reports a failure to decode an SSE event
///    as the raw `DecodingError` rather than as ``decodingError(_:)``.
public enum APIError: LocalizedError {
    /// No HTTP response was produced at all: connection failure, timeout, or cancellation.
    ///
    /// Wraps the transport's error, usually a `TransportError` around a `URLError`. A
    /// response that arrived and merely failed is not this case — that is
    /// ``httpError(statusCode:data:)``. Retrying is often reasonable here and rarely is
    /// for the others.
    case networkError(Error)
    /// A 2xx body did not decode into the contract's `Output`.
    ///
    /// Wraps the underlying `DecodingError`, which names the key that was missing or the
    /// wrong type. The bytes that failed are not carried here — they go to the matching
    /// ``HTTPLog/decodingError(endpoint:error:data:targetType:)`` entry, emitted just
    /// before this is thrown, which is the only place to recover them.
    case decodingError(Error)
    /// The base URL and the contract's resolved path did not combine into a usable URL.
    ///
    /// Thrown before anything is sent, so no log entry or event accompanies it. In
    /// practice: a base URL `URLComponents` rejects, or a path parameter substituted in
    /// with characters that are not URL-legal.
    case invalidURL
    /// Never thrown by this package.
    ///
    /// A response the transport cannot interpret arrives as ``networkError(_:)`` wrapping
    /// `TransportError.invalidResponse`.
    case invalidResponse
    /// A 401 or a 403, with the difference discarded.
    ///
    /// The body is dropped too. To tell "sign in again" from "this account may not do
    /// that", or to show what the server said, read
    /// ``HTTPEvent/unauthorized(endpoint:data:)`` and ``HTTPEvent/forbidden(endpoint:data:)``
    /// off the `events` stream, which keep both.
    case unauthorized
    /// Any other non-2xx response, with the body kept verbatim.
    ///
    /// `data` is exactly what the server sent, undecoded. This is what you get for a
    /// status your group's `decodeError` did not claim.
    case httpError(statusCode: Int, data: Data)

    /// A fixed description for logs and debugger output.
    ///
    /// Not display copy: there is no localization behind it and no user-facing wording
    /// has been chosen for it. Map the case to your own message before showing anything.
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
