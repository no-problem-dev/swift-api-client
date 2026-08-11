import Foundation

/// Supplies the credential for a request, resolved when the request is built rather than when the client is created.
///
/// ``APIClientImpl`` calls this once per call and attaches the result the way the
/// contract's `AuthScheme` says: an `Authorization: Bearer` header, a named header, or
/// a query item. Implement it over a keychain read or an OAuth library.
///
/// Three behaviours the signature does not show:
///
/// - Returning `nil` sends the request **unauthenticated** rather than failing it.
///   You learn about it from the server's 401.
/// - Throwing fails the call before anything is sent, and your error propagates as
///   itself — it is not wrapped in ``APIError``.
/// - **Retries do not come back here.** The token is baked into the request before the
///   retry policy runs, so every attempt of one call carries the same token, and a 401
///   never triggers a refresh on its own.
///
/// Refresh therefore belongs inside this method: check expiry and renew before
/// returning. Nothing upstream serializes these calls, so an app that fires several
/// requests at once will enter this method several times concurrently — deduplicate the
/// renewal yourself if your token endpoint cannot absorb that. React to a rejected
/// token by observing `APIClient.events` for ``HTTPEvent/unauthorized(endpoint:data:)``.
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
