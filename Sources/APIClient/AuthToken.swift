import Foundation

/// The credential in force for one client: resolved on demand, shared by everything that
/// asks at the same time, and dropped when the server rejects it.
///
/// ``APIClientImpl`` is a `struct` holding a reference to one of these, so its copies share
/// a credential the way they already share a telemetry channel.
///
/// Two things this settles that calling ``AuthTokenProvider/fetchToken()`` once per request
/// does not.
///
/// - **A burst enters the provider once.** Concurrent callers join the fetch that is already
///   running instead of starting their own. A provider that renews on expiry would otherwise
///   fire one renewal per request, and rotating refresh tokens invalidate each other.
/// - **A 401 can be answered.** ``refreshed(scopes:rejecting:)`` throws away what the server
///   rejected and asks the provider again, which is what lets one call retry with a new
///   token rather than reusing the token that just failed.
actor AuthToken {
    /// Tells "resolved to no credential" apart from "not resolved yet", which a bare
    /// dictionary of optionals cannot express.
    private struct Resolved {
        let token: String?
    }

    private let provider: AuthTokenProvider?
    private var resolved: [String: Resolved] = [:]
    private var inFlight: [String: (era: Int, task: Task<String?, Error>)] = [:]
    /// Bumped when a token is rejected, so a fetch that predates the rejection is not joined.
    private var era: [String: Int] = [:]

    init(provider: AuthTokenProvider?) {
        self.provider = provider
    }

    /// The token to attach, fetching it if none has been resolved since the last rejection.
    ///
    /// - Parameter scopes: The contract's `requiredScopes`, which reach a ``ScopedAuthTokenProvider``.
    /// - Returns: The token, or `nil` when there is no provider or it declined to supply one.
    func value(scopes: [String]) async throws -> String? {
        let key = key(for: scopes)
        if let resolved = resolved[key] { return resolved.token }
        return try await fetch(key: key, scopes: scopes)
    }

    /// Drops the rejected token and asks the provider for another one.
    ///
    /// When a concurrent call has already replaced it, that replacement is returned rather
    /// than a second renewal being started — which is what keeps a burst of 401s from
    /// firing one refresh each.
    ///
    /// - Parameters:
    ///   - scopes: The contract's `requiredScopes`.
    ///   - rejected: The token the server answered 401 to.
    /// - Returns: The provider's new token, which may equal `rejected` if it has none to offer.
    func refreshed(scopes: [String], rejecting rejected: String?) async throws -> String? {
        let key = key(for: scopes)
        if let resolved = resolved[key], resolved.token != rejected { return resolved.token }
        era[key, default: 0] += 1
        resolved.removeValue(forKey: key)
        return try await fetch(key: key, scopes: scopes)
    }

    private func fetch(key: String, scopes: [String]) async throws -> String? {
        let era = era[key, default: 0]
        if let existing = inFlight[key], existing.era == era { return try await existing.task.value }

        let provider = self.provider
        let task = Task<String?, Error> {
            if let scoped = provider as? ScopedAuthTokenProvider {
                return try await scoped.fetchToken(scopes: scopes)
            }
            return try await provider?.fetchToken()
        }
        inFlight[key] = (era, task)

        do {
            let token = try await task.value
            clearInFlight(key: key, era: era)
            if self.era[key, default: 0] == era { resolved[key] = Resolved(token: token) }
            return token
        } catch {
            clearInFlight(key: key, era: era)
            throw error
        }
    }

    private func clearInFlight(key: String, era: Int) {
        if inFlight[key]?.era == era { inFlight.removeValue(forKey: key) }
    }

    /// Scopes only separate credentials for a ``ScopedAuthTokenProvider``; every other
    /// provider answers one question and gets one entry.
    private func key(for scopes: [String]) -> String {
        provider is ScopedAuthTokenProvider ? scopes.sorted().joined(separator: " ") : ""
    }
}
