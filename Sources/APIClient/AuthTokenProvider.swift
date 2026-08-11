import Foundation

/// Supplies the credential for a request, resolved when the request is built rather than when the client is created.
///
/// ``APIClientImpl`` calls this when it has no token in hand and attaches the result the
/// way the contract's `AuthScheme` says: an `Authorization: Bearer` header, a named
/// header, or a query item. Implement it over a keychain read or an OAuth library.
///
/// Three behaviours the signature does not show:
///
/// - Returning `nil` sends the request **unauthenticated** rather than failing it.
///   You learn about it from the server's 401.
/// - Throwing fails the call before anything is sent, and your error propagates as
///   itself — it is not wrapped in ``APIError``.
/// - **You are not called once per request.** The resolved token is held and reused, so
///   this method runs when there is nothing to reuse and again when a 401 throws away
///   what there was. A burst of concurrent requests enters it once, not once per request,
///   which is what keeps a provider that renews on expiry from firing one renewal per
///   request — with rotating refresh tokens, those invalidate each other.
///
/// So a plain read is enough here; the client asks again when it needs to. Renewing on
/// expiry inside this method still works and is not duplicated. React to a rejected token
/// by observing `APIClient.events` for ``HTTPEvent/unauthorized(endpoint:data:)``.
///
/// Use ``ScopedAuthTokenProvider`` instead when the endpoint's scopes should reach you.
public protocol AuthTokenProvider: Sendable {
    /// Returns the credential to attach, or `nil` to let the request go out without one.
    ///
    /// - Returns: The token, or `nil` to proceed unauthenticated.
    /// - Throws: Any error, which fails the call unwrapped and before the request is sent.
    func fetchToken() async throws -> String?
}

/// An ``AuthTokenProvider`` that is told which scopes the endpoint declared.
///
/// ``APIClientImpl`` tests for this conformance on every call, and when it finds it
/// passes the contract's `requiredScopes` — the endpoint's own, or the group's when the
/// endpoint declares none.
///
/// This is not a way to keep several tokens and pick between them: OAuth issues one
/// access token, and its scopes record what the user granted at authorization time. The
/// use is to check the grant before spending a request. If an endpoint needs a scope the
/// user has not granted, start incremental authorization here instead of sending a call
/// that can only come back 403.
public protocol ScopedAuthTokenProvider: AuthTokenProvider {
    /// Returns the credential for an endpoint that declared these scopes.
    ///
    /// - Parameter scopes: The contract's `requiredScopes`, falling back to the group's; empty when neither declares any.
    func fetchToken(scopes: [String]) async throws -> String?
}

extension ScopedAuthTokenProvider {
    /// Satisfies the unscoped requirement so conformers only write ``fetchToken(scopes:)``.
    ///
    /// Reached only from a caller that has no endpoint in hand, which is why it asks for
    /// nothing rather than guessing a default set.
    public func fetchToken() async throws -> String? {
        try await fetchToken(scopes: [])
    }
}
