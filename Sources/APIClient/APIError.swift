import Foundation

/// What this package throws on its own behalf — which is not everything a call can throw.
///
/// Order your `catch` clauses accordingly:
///
/// 1. **Your group's error.** When an `APIContractGroup` implements `decodeError` and
///    returns a value for a response, that value is thrown *instead of* an `APIError`.
///    A `catch APIError.httpError` for a status your group maps will never run.
/// 2. **`APIError`.** Everything below.
/// 3. **Anything else.** One path bypasses this type: a throwing ``AuthTokenProvider``
///    fails the call with its own error, unwrapped, before the request is sent.
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
    /// A group or endpoint header names the header the contract's `AuthScheme` just filled.
    ///
    /// Thrown before anything is sent, because the request would otherwise go out with one
    /// of two credentials chosen by ordering alone and come back 401 with nothing to say
    /// why. Either drop the header, or declare `AuthScheme.none` on the contract and let
    /// the header be the credential.
    case conflictingAuthHeader(name: String)
    /// A 401: the credential was rejected. `data` is the body the server sent with it.
    ///
    /// Signing in again is the response to this one. Distinct from ``forbidden(data:)``,
    /// where a new session will not help.
    case unauthorized(data: Data)
    /// A 403: the credential was accepted and the operation is still not permitted.
    ///
    /// Look at scopes, roles, or plan limits — `data` is the body the server sent, which
    /// usually says which.
    case forbidden(data: Data)
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
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .invalidURL:
            return "Invalid URL"
        case .conflictingAuthHeader(let name):
            return "Header \(name) collides with the credential the contract's AuthScheme resolved"
        case .unauthorized:
            return "Authentication required"
        case .forbidden:
            return "Not permitted for this account"
        case .httpError(let statusCode, _):
            return "HTTP error: \(statusCode)"
        }
    }
}
