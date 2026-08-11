import APIContract
import Foundation

/// The label on an ``HTTPEvent`` or ``HTTPLog`` saying which call produced it.
///
/// Telemetry only. Nothing here is used to build a request — the contract owns the
/// method and path that go on the wire — so this is a value to group log lines and
/// metrics by, not a request you can send.
public struct APIEndpoint: Sendable {
    /// The contract's path with its parameters already substituted, without the base URL: `/v1/users/42`.
    ///
    /// Substitution means this is high-cardinality. Aggregating analytics on it produces
    /// one bucket per user id; group by contract type instead, and keep the path for
    /// reading individual log lines.
    public let path: String
    /// The method the request was sent with, taken from the contract.
    public let method: APIMethod

    /// Creates a label by hand, which outside of tests is rarely what you want — the client fills these in.
    ///
    /// - Parameters:
    ///   - path: A resolved path such as `/v1/users`.
    ///   - method: Defaults to `.get`.
    public init(
        path: String,
        method: APIMethod = .get
    ) {
        self.path = path
        self.method = method
    }
}
