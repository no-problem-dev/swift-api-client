import APIContract
import HTTPTransport
import Foundation
import StructuredDataCore

/// The seam an app depends on to run contracts: one transport, one codec, both request shapes.
///
/// Buffered calls (`APIExecutable`) and SSE calls (`StreamingAPIExecutable`) are served
/// from the same configuration, so the streaming form of an endpoint cannot drift away
/// from the buffered form in key style, date format, or authentication.
///
/// Depend on this protocol where you want to hand a test a canned client. Depend on
/// ``APIClientImpl`` and substitute its transport instead where you want the real
/// request-building path — URL assembly, header precedence, error mapping — under test.
public protocol APIClient: APIExecutable, StreamingAPIExecutable {
    /// Encodes a value with the same key and date strategies the client applies to request bodies.
    ///
    /// For contracts that have to assemble a body by hand — a multipart part, a JSON
    /// string embedded in another field — and must not disagree with the `keyStyle`
    /// and `dateStrategy` the rest of the client uses.
    ///
    /// - Parameter value: The value to encode.
    /// - Returns: The JSON encoding of `value`.
    /// - Throws: Whatever the body encoder throws, typically `EncodingError`.
    func encode<T: Encodable>(_ value: T) throws -> Data

    /// Responses that deserve one app-wide reaction rather than a `catch` at every call site: 401, 403, 429, 503, other 5xx.
    ///
    /// Drive logout, a maintenance screen, or a rate-limit banner from here. Events do
    /// not replace the thrown error — the call still fails — they save every call site
    /// from repeating the same response to it.
    ///
    /// Every observer sees every event, and an event emitted before anyone was observing
    /// is not kept — see ``TelemetryStream``.
    ///
    /// Only buffered calls emit events. Failures from ``APIClientImpl/execute(_:)`` and
    /// ``APIClientImpl/executeEventStream(_:)`` never reach this stream.
    var events: TelemetryStream<HTTPEvent> { get }

    /// Every completed request, successful or not, in a shape a console or an analytics sink can take.
    ///
    /// Same delivery as ``events``, and the same blind spot: SSE calls produce no entries.
    var logs: TelemetryStream<HTTPLog> { get }
}

/// The wire format for `Date` in request and response bodies.
///
/// Named here so that configuring a client does not require importing the
/// serialization package: `dateStrategy: .llmAPIDefault` resolves through this alias.
public typealias DateStrategy = DateCodingStrategy

/// How Swift property names are translated to JSON object keys.
///
/// Whichever style you pass to ``APIClientImpl/init(baseURL:transport:authTokenProvider:timeout:defaultHeaders:retryPolicy:rateLimitMapping:keyStyle:dateStrategy:)``
/// governs encoding and decoding alike, so a value written to the API and read back
/// cannot silently disagree with itself. Setting it once replaces writing `CodingKeys`
/// on every payload type.
public enum APIKeyStyle: Sendable {
    /// Send the Swift property names unchanged.
    case `default`
    /// `camelCase` in Swift, `snake_case` on the wire — the usual REST convention.
    case snakeCase
    /// `camelCase` in Swift, `kebab-case` on the wire.
    case kebabCase

    var encoding: EncodingOptions.KeyStrategy {
        switch self {
        case .default: return .useDefaultKeys
        case .snakeCase: return .convertToSnakeCase
        case .kebabCase: return .convertToKebabCase
        }
    }

    var decoding: DecodingOptions.KeyStrategy {
        switch self {
        case .default: return .useDefaultKeys
        case .snakeCase: return .convertFromSnakeCase
        case .kebabCase: return .convertFromKebabCase
        }
    }
}
