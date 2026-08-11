import Foundation

/// A response the whole app reacts to the same way, delivered once instead of at every call site.
///
/// Read these from `APIClientImpl.events`. The call that produced the event still throws;
/// this stream is what spares each call site from repeating the logout, the maintenance
/// screen, or the rate-limit banner.
///
/// Every case carries the raw response body as `data`. Only buffered calls emit events —
/// an SSE call that fails produces none.
///
/// ```swift
/// Task {
///     for await event in client.events {
///         switch event {
///         case .unauthorized: await authManager.handleLogout()
///         case .rateLimited(_, let retry, _): scheduleRetry(after: retry)
///         default: break
///         }
///     }
/// }
/// ```
public enum HTTPEvent: Sendable {
    /// 401: the credential was rejected. Clear the session and re-authenticate.
    ///
    /// Distinct from ``forbidden(endpoint:data:)`` here, though ``APIError`` collapses
    /// both into ``APIError/unauthorized``.
    case unauthorized(endpoint: APIEndpoint, data: Data)
    /// 403: the credential was accepted and the operation is still not permitted.
    ///
    /// Signing in again will not help. Look at scopes, roles, or plan limits — and
    /// `data` usually says which.
    case forbidden(endpoint: APIEndpoint, data: Data)
    /// 429: back off. `retryAfter` is the wait in seconds, when the server gave a usable one.
    ///
    /// It is `nil` when the header is absent and also when it holds an HTTP-date rather
    /// than a number, which this package does not parse. Fall back to your own backoff
    /// on `nil` instead of retrying at once.
    case rateLimited(endpoint: APIEndpoint, retryAfter: TimeInterval?, data: Data)
    /// 503: the service is down or in maintenance. The usual home for a maintenance screen.
    case serviceUnavailable(endpoint: APIEndpoint, data: Data)
    /// Any other 5xx, with the exact status in `statusCode`.
    ///
    /// 503 arrives as ``serviceUnavailable(endpoint:data:)`` and never here.
    case serverError(statusCode: Int, endpoint: APIEndpoint, data: Data)
}
