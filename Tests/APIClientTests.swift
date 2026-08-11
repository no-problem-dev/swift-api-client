import XCTest
import Foundation
@testable import APIClient
import APIContract
// `HTTPStatusError`'s memberwise initializer is internal to HTTPTransport, so the only way
// to stage the status failure a streaming transport raises is to reach in.
@testable import HTTPTransport

// MARK: - APIEndpoint Tests

final class APIEndpointTests: XCTestCase {
    func testInitWithDefaults() {
        let endpoint = APIEndpoint(path: "/v1/users")
        XCTAssertEqual(endpoint.path, "/v1/users")
        XCTAssertEqual(endpoint.method, .get)
    }

    func testInitWithAllParameters() {
        let endpoint = APIEndpoint(path: "/v1/users", method: .post)
        XCTAssertEqual(endpoint.path, "/v1/users")
        XCTAssertEqual(endpoint.method, .post)
    }
}

// MARK: - APIError Tests

final class APIErrorTests: XCTestCase {
    func testNetworkErrorDescription() {
        let error = APIError.networkError(NSError(domain: "T", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network unreachable"]))
        XCTAssertEqual(error.errorDescription, "Network error: Network unreachable")
    }
    func testInvalidURLDescription() { XCTAssertEqual(APIError.invalidURL.errorDescription, "Invalid URL") }
    func testUnauthorizedDescription() { XCTAssertEqual(APIError.unauthorized(data: Data()).errorDescription, "Authentication required") }
    func testForbiddenDescription() { XCTAssertEqual(APIError.forbidden(data: Data()).errorDescription, "Not permitted for this account") }
    func testHTTPErrorDescription() { XCTAssertEqual(APIError.httpError(statusCode: 404, data: Data()).errorDescription, "HTTP error: 404") }
    func testConformsToLocalizedError() {
        let error: LocalizedError = APIError.invalidURL
        XCTAssertNotNil(error.errorDescription)
    }
}

// MARK: - HTTPLog Tests

final class HTTPLogTests: XCTestCase {
    func testSuccessDescription() {
        let log = HTTPLog.success(endpoint: APIEndpoint(path: "/v1/users"), statusCode: 200, data: Data(#"{"id":1}"#.utf8))
        XCTAssertTrue(log.description.contains("API REQUEST SUCCESS"))
        XCTAssertTrue(log.description.contains("GET /v1/users"))
    }
    func testHTTPErrorDescription() {
        let log = HTTPLog.httpError(endpoint: APIEndpoint(path: "/v1/x"), statusCode: 404, data: Data(#"{"error":"Not Found"}"#.utf8))
        XCTAssertTrue(log.description.contains("HTTP ERROR"))
        XCTAssertTrue(log.description.contains("Not Found"))
    }
    func testLargeDataTruncation() {
        let log = HTTPLog.success(endpoint: APIEndpoint(path: "/x"), statusCode: 200, data: Data(repeating: 65, count: 15000))
        XCTAssertTrue(log.description.contains("too large to display"))
    }

    /// The pathological body is the error one — a 500 answering with a large HTML page.
    func testLargeErrorBodyIsElided() {
        let page = Data(String(repeating: "<div>padding</div>", count: 2000).utf8)
        XCTAssertGreaterThan(page.count, 10000)
        let log = HTTPLog.httpError(endpoint: APIEndpoint(path: "/x"), statusCode: 500, data: page)
        XCTAssertTrue(log.description.contains("too large to display"))
        XCTAssertFalse(log.description.contains("<div>padding</div>"))
    }

    /// The body that failed to decode is capped on the same terms.
    func testLargeDecodeFailureBodyIsElided() {
        let body = Data(String(repeating: #"{"unexpected":"value"},"#, count: 1000).utf8)
        XCTAssertGreaterThan(body.count, 10000)
        let log = HTTPLog.decodingError(
            endpoint: APIEndpoint(path: "/x"), error: "keyNotFound", data: body, targetType: "TestResponse"
        )
        XCTAssertTrue(log.description.contains("too large to display"))
        XCTAssertFalse(log.description.contains(#""unexpected""#))
    }

    /// Capping must not cost the small bodies their contents.
    func testSmallErrorBodyStillShown() {
        let log = HTTPLog.httpError(endpoint: APIEndpoint(path: "/x"), statusCode: 500, data: Data(#"{"error":"boom"}"#.utf8))
        XCTAssertTrue(log.description.contains("boom"))
    }
}

// MARK: - HTTPEvent Tests

final class HTTPEventTests: XCTestCase {
    func testRateLimitedEvent() {
        let event = HTTPEvent.rateLimited(endpoint: APIEndpoint(path: "/v1/api"), retryAfter: 60, data: Data())
        guard case .rateLimited(let ep, let retry, _) = event else { return XCTFail("expected rateLimited") }
        XCTAssertEqual(ep.path, "/v1/api")
        XCTAssertEqual(retry, 60)
    }
    func testServerErrorEvent() {
        let event = HTTPEvent.serverError(statusCode: 500, endpoint: APIEndpoint(path: "/e"), data: Data())
        guard case .serverError(let code, _, _) = event else { return XCTFail("expected serverError") }
        XCTAssertEqual(code, 500)
    }
}

// MARK: - Test Contracts & helpers

private enum TestAPIGroup: APIContractGroup {
    static let basePath = "/v1"
    static let auth: AuthScheme = .bearer
    static let endpoints: [EndpointDescriptor] = []
    static func decodeError(statusCode: Int, data: Data, headers: [String: String], decoder: any APIBodyDecoder) -> (any Error)? {
        guard statusCode == 422 else { return nil }
        return (try? decoder.decode(TestErrorBody.self, from: data)).map { CustomError.validation($0.message) }
    }
}

struct TestErrorBody: Codable, Sendable { let message: String }
enum CustomError: Error, Equatable { case validation(String) }

struct TestResponse: Codable, Sendable, Equatable { let id: Int; let name: String }
struct PostBody: Codable, Sendable { let userName: String }

private struct GetContract: APIContract, APIInput {
    typealias Group = TestAPIGroup
    typealias Input = Self
    typealias Output = TestResponse
    static let method: APIMethod = .get
    static let subPath = "/users"
    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { nil }
    static func decode(pathParameters: [String: String], queryParameters: [String: String], body: Data?, decoder: any APIBodyDecoder) throws -> Self { Self() }
}

private struct PostContract: APIContract, APIInput {
    typealias Group = TestAPIGroup
    typealias Input = Self
    typealias Output = TestResponse
    static let method: APIMethod = .post
    static let subPath = "/users"
    let body: PostBody
    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { try encoder.encode(body) }
    static func decode(pathParameters: [String: String], queryParameters: [String: String], body: Data?, decoder: any APIBodyDecoder) throws -> Self { fatalError() }
}

private struct QueryContract: APIContract, APIInput {
    typealias Group = TestAPIGroup
    typealias Input = Self
    typealias Output = TestResponse
    static let method: APIMethod = .get
    static let subPath = "/users"
    let page: Int
    var queryParameters: [String: String]? { ["page": "\(page)"] }
    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { nil }
    static func decode(pathParameters: [String: String], queryParameters: [String: String], body: Data?, decoder: any APIBodyDecoder) throws -> Self { Self(page: 0) }
}

private struct ErrorContract: APIContract, APIInput {
    typealias Group = TestAPIGroup
    typealias Input = Self
    typealias Output = TestResponse
    static let method: APIMethod = .get
    static let subPath = "/fail"
    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { nil }
    static func decode(pathParameters: [String: String], queryParameters: [String: String], body: Data?, decoder: any APIBodyDecoder) throws -> Self { Self() }
}

struct StreamEvent: Codable, Sendable, Equatable { let delta: String }

private struct StreamContract: StreamingAPIContract, APIInput {
    typealias Group = TestAPIGroup
    typealias Input = Self
    typealias Event = StreamEvent
    static let method: APIMethod = .post
    static let subPath = "/stream"
    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { nil }
    static func decode(pathParameters: [String: String], queryParameters: [String: String], body: Data?, decoder: any APIBodyDecoder) throws -> Self { Self() }
}

/// Reproduces an OpenAI-compatible contract whose base URL is already the complete
/// endpoint: both basePath and subPath are empty.
private enum EmptyPathAPIGroup: APIContractGroup {
    static let basePath = ""
    static let auth: AuthScheme = .bearer
    static let endpoints: [EndpointDescriptor] = []
    static func decodeError(statusCode: Int, data: Data, headers: [String: String], decoder: any APIBodyDecoder) -> (any Error)? { nil }
}

private struct EmptyPathContract: APIContract, APIInput {
    typealias Group = EmptyPathAPIGroup
    typealias Input = Self
    typealias Output = TestResponse
    static let method: APIMethod = .post
    static let subPath = ""
    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { nil }
    static func decode(pathParameters: [String: String], queryParameters: [String: String], body: Data?, decoder: any APIBodyDecoder) throws -> Self { Self() }
}

private struct StaticToken: AuthTokenProvider { let token: String?; func fetchToken() async throws -> String? { token } }

private func okResponse(_ json: String) -> HTTPResponse {
    HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Data(json.utf8))
}

// MARK: - APIClientImpl Tests (MockTransport)

final class APIClientImplTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    func testGetDecodesOutput() async throws {
        let mock = MockTransport { _ in okResponse(#"{"id":1,"name":"Ada"}"#) }
        let client = APIClientImpl(baseURL: baseURL, transport: mock)
        let response = try await client.executeWithResponse(GetContract())
        XCTAssertEqual(response.output, TestResponse(id: 1, name: "Ada"))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(mock.recordedRequests.first?.url.path, "/v1/users")
    }

    func testPostEncodesBody() async throws {
        let mock = MockTransport { _ in okResponse(#"{"id":2,"name":"x"}"#) }
        let client = APIClientImpl(baseURL: baseURL, transport: mock)
        _ = try await client.execute(PostContract(body: PostBody(userName: "ada")))
        let body = try XCTUnwrap(mock.recordedRequests.first?.body)
        XCTAssertEqual(String(decoding: body, as: UTF8.self), #"{"userName":"ada"}"#)
        XCTAssertEqual(mock.recordedRequests.first?.method, "POST")
    }

    func testSnakeCaseKeyStyle() async throws {
        let mock = MockTransport { _ in okResponse(#"{"id":1,"name":"x"}"#) }
        let client = APIClientImpl(baseURL: baseURL, transport: mock, keyStyle: .snakeCase)
        _ = try await client.execute(PostContract(body: PostBody(userName: "ada")))
        let body = try XCTUnwrap(mock.recordedRequests.first?.body)
        XCTAssertEqual(String(decoding: body, as: UTF8.self), #"{"user_name":"ada"}"#)
    }

    func testQueryParameters() async throws {
        let mock = MockTransport { _ in okResponse(#"{"id":1,"name":"x"}"#) }
        let client = APIClientImpl(baseURL: baseURL, transport: mock)
        _ = try await client.execute(QueryContract(page: 3))
        XCTAssertEqual(mock.recordedRequests.first?.url.query, "page=3")
    }

    /// Regression gate: an empty contract path must not gain a trailing slash.
    /// Groq answered `.../chat/completions/` with `Unknown request URL`.
    func testEmptyPathDoesNotAddTrailingSlash() async throws {
        let mock = MockTransport { _ in okResponse(#"{"id":1,"name":"x"}"#) }
        let fullURL = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        let client = APIClientImpl(baseURL: fullURL, transport: mock)
        _ = try await client.executeWithResponse(EmptyPathContract())
        XCTAssertEqual(
            mock.recordedRequests.first?.url.absoluteString,
            "https://api.groq.com/openai/v1/chat/completions"
        )
    }

    func testBearerAuthHeader() async throws {
        let mock = MockTransport { _ in okResponse(#"{"id":1,"name":"x"}"#) }
        let client = APIClientImpl(baseURL: baseURL, transport: mock, authTokenProvider: StaticToken(token: "secret"))
        _ = try await client.execute(GetContract())
        XCTAssertEqual(mock.recordedRequests.first?.headers["authorization"], "Bearer secret")
    }

    func testErrorStatusMapsToAPIError() async {
        let mock = MockTransport(status: 404, body: Data(#"{"error":"nope"}"#.utf8))
        let client = APIClientImpl(baseURL: baseURL, transport: mock)
        do {
            _ = try await client.executeWithResponse(ErrorContract())
            XCTFail("expected error")
        } catch let APIError.httpError(statusCode, _) {
            XCTAssertEqual(statusCode, 404)
        } catch { XCTFail("unexpected: \(error)") }
    }

    func testCustomErrorDecode() async {
        let mock = MockTransport(status: 422, body: Data(#"{"message":"bad input"}"#.utf8))
        let client = APIClientImpl(baseURL: baseURL, transport: mock)
        do {
            _ = try await client.executeWithResponse(ErrorContract())
            XCTFail("expected error")
        } catch CustomError.validation(let message) {
            XCTAssertEqual(message, "bad input")
        } catch { XCTFail("unexpected: \(error)") }
    }

    func testRetriesViaTransport() async throws {
        let mock = MockTransport([
            .response(HTTPResponse(status: 429, headers: ["retry-after": "0"], body: Data())),
            .response(okResponse(#"{"id":9,"name":"ok"}"#)),
        ])
        let client = APIClientImpl(
            baseURL: baseURL, transport: mock,
            retryPolicy: ExponentialBackoff(maxAttempts: 3, baseDelay: 0)
        )
        let response = try await client.executeWithResponse(GetContract())
        XCTAssertEqual(response.output.id, 9)
        XCTAssertEqual(mock.recordedRequests.count, 2)
    }

    func testStreamingDecodesEvents() async throws {
        let sse = "data: {\"delta\":\"a\"}\n\ndata: {\"delta\":\"b\"}\n\ndata: [DONE]\n\n"
        let mock = MockTransport(streamChunks: [Data(sse.utf8)])
        let client = APIClientImpl(baseURL: baseURL, transport: mock)
        var deltas: [String] = []
        for try await event in client.execute(StreamContract()) {
            deltas.append(event.delta)
        }
        XCTAssertEqual(deltas, ["a", "b"])
        XCTAssertEqual(mock.recordedRequests.first?.headers["accept"], "text/event-stream")
    }

    func testExecuteRawReturnsBinaryBody() async throws {
        let audio = Data([0x49, 0x44, 0x33, 0x04, 0x00])
        let mock = MockTransport { _ in HTTPResponse(status: 200, headers: ["Content-Type": "audio/mpeg"], body: audio) }
        let client = APIClientImpl(baseURL: baseURL, transport: mock)
        let response = try await client.executeRaw(GetContract())
        XCTAssertEqual(response.output, audio)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(mock.recordedRequests.first?.headers["accept"], "*/*")
    }

    func testExecuteRawMapsError() async throws {
        let mock = MockTransport(status: 422, body: Data(#"{"message":"bad"}"#.utf8))
        let client = APIClientImpl(baseURL: baseURL, transport: mock)
        do {
            _ = try await client.executeRaw(ErrorContract())
            XCTFail("expected throw")
        } catch CustomError.validation(let msg) {
            XCTAssertEqual(msg, "bad")
        }
    }

    func testEventStreamPreservesEventNames() async throws {
        let sse = "event: start\ndata: {\"x\":1}\n\nevent: delta\ndata: hello\n\n"
        let mock = MockTransport(streamChunks: [Data(sse.utf8)])
        let client = APIClientImpl(baseURL: baseURL, transport: mock)
        var events: [(String?, String)] = []
        for try await sse in client.executeEventStream(GetContract()) {
            events.append((sse.event, sse.data))
        }
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].0, "start")
        XCTAssertEqual(events[0].1, "{\"x\":1}")
        XCTAssertEqual(events[1].0, "delta")
        XCTAssertEqual(events[1].1, "hello")
        XCTAssertEqual(mock.recordedRequests.first?.headers["accept"], "text/event-stream")
    }
}

// MARK: - 401 and 403 are different answers

final class RejectedRequestTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    /// "Sign in again" must be distinguishable from "this account may not do that", and
    /// what the server said must survive into the thrown value.
    func testUnauthorizedCarriesItsBody() async {
        let body = #"{"error":"token expired"}"#
        let mock = MockTransport(status: 401, body: Data(body.utf8))
        let client = APIClientImpl(baseURL: baseURL, transport: mock)
        do {
            _ = try await client.executeWithResponse(ErrorContract())
            XCTFail("expected error")
        } catch let APIError.unauthorized(data) {
            XCTAssertEqual(String(decoding: data, as: UTF8.self), body)
        } catch { XCTFail("unexpected: \(error)") }
    }

    func testForbiddenIsItsOwnCaseAndCarriesItsBody() async {
        let body = #"{"error":"plan does not include this"}"#
        let mock = MockTransport(status: 403, body: Data(body.utf8))
        let client = APIClientImpl(baseURL: baseURL, transport: mock)
        do {
            _ = try await client.executeWithResponse(ErrorContract())
            XCTFail("expected error")
        } catch let APIError.forbidden(data) {
            XCTAssertEqual(String(decoding: data, as: UTF8.self), body)
        } catch { XCTFail("unexpected: \(error)") }
    }
}

// MARK: - A header may not quietly take the credential's place

private enum OverridingAuthGroup: APIContractGroup {
    static let basePath = "/v1"
    static let auth: AuthScheme = .bearer
    static let endpoints: [EndpointDescriptor] = []
    static let commonHeaders: [String: String] = ["authorization": "Basic c3RhbGU="]
}

private struct OverriddenAuthContract: APIContract, APIInput {
    typealias Group = OverridingAuthGroup
    typealias Input = Self
    typealias Output = TestResponse
    static let method: APIMethod = .get
    static let subPath = "/users"
    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { nil }
    static func decode(pathParameters: [String: String], queryParameters: [String: String], body: Data?, decoder: any APIBodyDecoder) throws -> Self { Self() }
}

/// Same group, but the endpoint is the one that collides.
private struct EndpointOverrideContract: APIContract, APIInput {
    typealias Group = TestAPIGroup
    typealias Input = Self
    typealias Output = TestResponse
    static let method: APIMethod = .get
    static let subPath = "/users"
    var additionalHeaders: [String: String] { ["Authorization": "Basic c3RhbGU="] }
    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { nil }
    static func decode(pathParameters: [String: String], queryParameters: [String: String], body: Data?, decoder: any APIBodyDecoder) throws -> Self { Self() }
}

/// A group header that is not the credential's must still apply.
private enum HarmlessHeaderGroup: APIContractGroup {
    static let basePath = "/v1"
    static let auth: AuthScheme = .bearer
    static let endpoints: [EndpointDescriptor] = []
    static let commonHeaders: [String: String] = ["X-Tenant": "acme"]
}

private struct HarmlessHeaderContract: APIContract, APIInput {
    typealias Group = HarmlessHeaderGroup
    typealias Input = Self
    typealias Output = TestResponse
    static let method: APIMethod = .get
    static let subPath = "/users"
    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { nil }
    static func decode(pathParameters: [String: String], queryParameters: [String: String], body: Data?, decoder: any APIBodyDecoder) throws -> Self { Self() }
}

/// A group header named `Authorization` with no token provider is the credential, not a collision.
private struct UnauthenticatedOverrideContract: APIContract, APIInput {
    typealias Group = OverridingAuthGroup
    typealias Input = Self
    typealias Output = TestResponse
    static let method: APIMethod = .get
    static let subPath = "/users"
    static let auth: AuthScheme = .none
    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { nil }
    static func decode(pathParameters: [String: String], queryParameters: [String: String], body: Data?, decoder: any APIBodyDecoder) throws -> Self { Self() }
}

final class CredentialHeaderCollisionTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    func testGroupHeaderMayNotReplaceTheResolvedToken() async {
        let mock = MockTransport { _ in okResponse(#"{"id":1,"name":"x"}"#) }
        let client = APIClientImpl(baseURL: baseURL, transport: mock, authTokenProvider: StaticToken(token: "secret"))
        do {
            _ = try await client.executeWithResponse(OverriddenAuthContract())
            XCTFail("expected the collision to be reported")
        } catch let APIError.conflictingAuthHeader(name) {
            XCTAssertEqual(name, "Authorization")
        } catch { XCTFail("unexpected: \(error)") }
        XCTAssertTrue(mock.recordedRequests.isEmpty, "nothing should be sent with a credential chosen by ordering")
    }

    func testEndpointHeaderMayNotReplaceTheResolvedToken() async {
        let mock = MockTransport { _ in okResponse(#"{"id":1,"name":"x"}"#) }
        let client = APIClientImpl(baseURL: baseURL, transport: mock, authTokenProvider: StaticToken(token: "secret"))
        do {
            _ = try await client.executeWithResponse(EndpointOverrideContract())
            XCTFail("expected the collision to be reported")
        } catch let APIError.conflictingAuthHeader(name) {
            XCTAssertEqual(name, "Authorization")
        } catch { XCTFail("unexpected: \(error)") }
    }

    func testUnrelatedGroupHeadersStillApply() async throws {
        let mock = MockTransport { _ in okResponse(#"{"id":1,"name":"x"}"#) }
        let client = APIClientImpl(baseURL: baseURL, transport: mock, authTokenProvider: StaticToken(token: "secret"))
        _ = try await client.executeWithResponse(HarmlessHeaderContract())
        XCTAssertEqual(mock.recordedRequests.first?.headers["x-tenant"], "acme")
        XCTAssertEqual(mock.recordedRequests.first?.headers["authorization"], "Bearer secret")
    }

    /// With nothing to collide with, the header is simply the credential.
    func testAuthorizationHeaderIsFineWhenTheClientResolvedNothing() async throws {
        let mock = MockTransport { _ in okResponse(#"{"id":1,"name":"x"}"#) }
        let client = APIClientImpl(baseURL: baseURL, transport: mock)
        _ = try await client.executeWithResponse(UnauthenticatedOverrideContract())
        XCTAssertEqual(mock.recordedRequests.first?.headers["authorization"], "Basic c3RhbGU=")
    }
}

// MARK: - Transports that fail the way a real one does

/// Fails `stream(_:)` with a chosen error, which `MockTransport` cannot do.
private final class FailingStreamTransport: HTTPTransport, HTTPStreamingTransport, @unchecked Sendable {
    let error: any Error
    init(error: any Error) { self.error = error }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse { throw error }
    func stream(_ request: HTTPRequest) -> AsyncThrowingStream<Data, Error> {
        let error = self.error
        return AsyncThrowingStream { continuation in continuation.finish(throwing: error) }
    }
}

// MARK: - Streaming failures reach the caller in the same shape as buffered ones

final class StreamingErrorMappingTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    /// A non-2xx on a stream must arrive as `APIError`, not the transport's `HTTPStatusError`.
    func testStreamingStatusErrorMapsToAPIError() async {
        let transport = FailingStreamTransport(
            error: HTTPStatusError(status: 404, headers: [:], body: Data(#"{"error":"nope"}"#.utf8))
        )
        let client = APIClientImpl(baseURL: baseURL, transport: transport)
        do {
            for try await _ in client.execute(StreamContract()) {}
            XCTFail("expected error")
        } catch let APIError.httpError(statusCode, data) {
            XCTAssertEqual(statusCode, 404)
            XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"error":"nope"}"#)
        } catch { XCTFail("unexpected: \(error)") }
    }

    /// The group's `decodeError` must claim a streaming failure too.
    func testStreamingStatusErrorRunsThroughGroupDecodeError() async {
        let transport = FailingStreamTransport(
            error: HTTPStatusError(status: 422, headers: [:], body: Data(#"{"message":"bad input"}"#.utf8))
        )
        let client = APIClientImpl(baseURL: baseURL, transport: transport)
        do {
            for try await _ in client.execute(StreamContract()) {}
            XCTFail("expected error")
        } catch CustomError.validation(let message) {
            XCTAssertEqual(message, "bad input")
        } catch { XCTFail("unexpected: \(error)") }
    }

    /// A message that will not decode must arrive as `APIError.decodingError`, not a raw `DecodingError`.
    func testStreamingDecodeFailureMapsToAPIError() async {
        let mock = MockTransport(streamChunks: [Data("data: {\"unexpected\":1}\n\n".utf8)])
        let client = APIClientImpl(baseURL: baseURL, transport: mock)
        do {
            for try await _ in client.execute(StreamContract()) {}
            XCTFail("expected error")
        } catch let APIError.decodingError(underlying) {
            XCTAssertTrue(underlying is DecodingError, "expected the DecodingError to be carried, got \(underlying)")
        } catch { XCTFail("unexpected: \(error)") }
    }

    /// A transport failure on a stream matches the buffered path's `.networkError`.
    func testStreamingTransportFailureMapsToNetworkError() async {
        let transport = FailingStreamTransport(error: TransportError.cancelled)
        let client = APIClientImpl(baseURL: baseURL, transport: transport)
        do {
            for try await _ in client.execute(StreamContract()) {}
            XCTFail("expected error")
        } catch let APIError.networkError(underlying) {
            XCTAssertTrue(underlying is TransportError)
        } catch { XCTFail("unexpected: \(error)") }
    }

    /// `buildRequest` failures must not be relabelled as transport failures.
    func testStreamingAuthProviderErrorPropagatesUnwrapped() async {
        let mock = MockTransport(streamChunks: [])
        let client = APIClientImpl(baseURL: baseURL, transport: mock, authTokenProvider: ThrowingToken())
        do {
            for try await _ in client.execute(StreamContract()) {}
            XCTFail("expected error")
        } catch is TokenUnavailable {
            // The provider's own error, unwrapped, as documented.
        } catch { XCTFail("unexpected: \(error)") }
    }
}

private struct TokenUnavailable: Error {}
private struct ThrowingToken: AuthTokenProvider {
    func fetchToken() async throws -> String? { throw TokenUnavailable() }
}

// MARK: - A response the transport cannot interpret

final class InvalidResponseTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    /// Pins where this condition actually lands: the transport owns the distinction and
    /// the client reports it as a network failure carrying `TransportError.invalidResponse`.
    func testUninterpretableResponseArrivesAsNetworkError() async {
        let transport = FailingStreamTransport(error: TransportError.invalidResponse)
        let client = APIClientImpl(baseURL: baseURL, transport: transport)
        do {
            _ = try await client.executeWithResponse(GetContract())
            XCTFail("expected error")
        } catch let APIError.networkError(underlying) {
            guard case TransportError.invalidResponse = underlying else {
                return XCTFail("expected TransportError.invalidResponse, got \(underlying)")
            }
        } catch { XCTFail("unexpected: \(error)") }
    }
}

// MARK: - Auth: refresh on 401 and one provider call for a concurrent burst

private actor TokenLedger {
    private(set) var calls = 0
    private var issued = 0
    /// Sleeps so a burst of callers genuinely overlaps.
    func next() async -> String {
        calls += 1
        try? await Task.sleep(nanoseconds: 20_000_000)
        issued += 1
        return "t\(issued)"
    }
    func rotating() -> String {
        calls += 1
        issued += 1
        return issued == 1 ? "old" : "new"
    }
}

private struct LedgerToken: AuthTokenProvider {
    let ledger: TokenLedger
    func fetchToken() async throws -> String? { await ledger.next() }
}

private struct RotatingToken: AuthTokenProvider {
    let ledger: TokenLedger
    func fetchToken() async throws -> String? { await ledger.rotating() }
}

final class AuthTokenResolutionTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    /// A burst of concurrent calls must enter the provider once, not once per call:
    /// a provider that renews on expiry would otherwise fire N renewals, and rotating
    /// refresh tokens invalidate each other.
    func testConcurrentCallsEnterTheProviderOnce() async throws {
        let ledger = TokenLedger()
        let mock = MockTransport { _ in okResponse(#"{"id":1,"name":"x"}"#) }
        let client = APIClientImpl(baseURL: baseURL, transport: mock, authTokenProvider: LedgerToken(ledger: ledger))

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { _ = try await client.executeWithResponse(GetContract()) }
            }
            try await group.waitForAll()
        }

        let calls = await ledger.calls
        XCTAssertEqual(calls, 1, "expected the concurrent burst to share one provider call, got \(calls)")
    }

    /// A 401 must be able to drive a refresh: the rejected token is dropped, the provider
    /// is asked again, and the call is retried with what it returned.
    func testUnauthorizedTriggersRefreshAndRetry() async throws {
        let ledger = TokenLedger()
        let mock = MockTransport { request in
            request.headers["authorization"] == "Bearer new"
                ? okResponse(#"{"id":7,"name":"refreshed"}"#)
                : HTTPResponse(status: 401, headers: [:], body: Data(#"{"error":"expired"}"#.utf8))
        }
        let client = APIClientImpl(baseURL: baseURL, transport: mock, authTokenProvider: RotatingToken(ledger: ledger))

        let response = try await client.executeWithResponse(GetContract())

        XCTAssertEqual(response.output.id, 7)
        XCTAssertEqual(mock.recordedRequests.count, 2)
        XCTAssertEqual(mock.recordedRequests.first?.headers["authorization"], "Bearer old")
        XCTAssertEqual(mock.recordedRequests.last?.headers["authorization"], "Bearer new")
    }

    /// The refresh is attempted once. A provider that keeps handing back a rejected token
    /// must not put the client in a loop, and the 401 must still reach the caller.
    func testRefreshIsNotRetriedForever() async {
        let mock = MockTransport { _ in HTTPResponse(status: 401, headers: [:], body: Data()) }
        let client = APIClientImpl(baseURL: baseURL, transport: mock, authTokenProvider: StaticToken(token: "same"))
        do {
            _ = try await client.executeWithResponse(GetContract())
            XCTFail("expected error")
        } catch {
            // A provider that returns the same token gains nothing from a second send.
            XCTAssertEqual(mock.recordedRequests.count, 1)
        }
    }
}

// MARK: - Telemetry reaches every observer and retains nothing for nobody

final class TelemetryStreamTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    /// Two observers must each see every event, rather than dividing them between them.
    func testEveryObserverSeesEveryEvent() async {
        let mock = MockTransport { _ in HTTPResponse(status: 401, headers: [:], body: Data()) }
        let client = APIClientImpl(baseURL: baseURL, transport: mock)

        var first = client.events.makeAsyncIterator()
        var second = client.events.makeAsyncIterator()

        _ = try? await client.executeWithResponse(ErrorContract())   // /v1/fail
        _ = try? await client.executeWithResponse(GetContract())     // /v1/users

        let a = await first.next()
        let b = await second.next()
        XCTAssertEqual(endpointPath(a), "/v1/fail")
        XCTAssertEqual(endpointPath(b), "/v1/fail", "the second observer received a different event, so the two are splitting one stream")
    }

    /// Nothing is kept for an observer that does not exist yet: a client nobody iterates
    /// must not hand its whole history to whoever subscribes later.
    func testLateObserverGetsNoBacklog() async {
        let mock = MockTransport { _ in HTTPResponse(status: 401, headers: [:], body: Data()) }
        let client = APIClientImpl(baseURL: baseURL, transport: mock)

        _ = try? await client.executeWithResponse(ErrorContract())   // nobody is listening

        var late = client.events.makeAsyncIterator()
        _ = try? await client.executeWithResponse(GetContract())

        let event = await late.next()
        XCTAssertEqual(endpointPath(event), "/v1/users", "a late observer was handed a retained event")
    }

    private func endpointPath(_ event: HTTPEvent?) -> String? {
        switch event {
        case .unauthorized(let endpoint, _), .forbidden(let endpoint, _),
             .serviceUnavailable(let endpoint, _), .serverError(_, let endpoint, _):
            return endpoint.path
        case .rateLimited(let endpoint, _, _):
            return endpoint.path
        case nil:
            return nil
        }
    }
}

// MARK: - Scope propagation (ScopedAuthTokenProvider)

/// Thread-safe box recording the scopes handed to `fetchToken(scopes:)`.
private final class ScopeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _scopes: [String]?
    var scopes: [String]? { lock.lock(); defer { lock.unlock() }; return _scopes }
    func record(_ value: [String]) { lock.lock(); _scopes = value; lock.unlock() }
}

private struct RecordingScopedToken: ScopedAuthTokenProvider {
    let token: String?
    let recorder: ScopeRecorder
    func fetchToken(scopes: [String]) async throws -> String? {
        recorder.record(scopes)
        return token
    }
}

private enum ScopedGroup: APIContractGroup {
    static let basePath = "/v1"
    static let auth: AuthScheme = .bearer
    static let endpoints: [EndpointDescriptor] = []
    static let requiredScopes: [String] = ["group.default"]
}

/// A contract that declares its own scopes.
private struct ScopedEndpointContract: APIContract, APIInput {
    typealias Group = ScopedGroup
    typealias Input = Self
    typealias Output = TestResponse
    static let method: APIMethod = .get
    static let subPath = "/scoped"
    static let requiredScopes: [String] = ["endpoint.read"]
    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { nil }
    static func decode(pathParameters: [String: String], queryParameters: [String: String], body: Data?, decoder: any APIBodyDecoder) throws -> Self { Self() }
}

/// A contract that declares none and inherits the group's.
private struct GroupScopedContract: APIContract, APIInput {
    typealias Group = ScopedGroup
    typealias Input = Self
    typealias Output = TestResponse
    static let method: APIMethod = .get
    static let subPath = "/inherited"
    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { nil }
    static func decode(pathParameters: [String: String], queryParameters: [String: String], body: Data?, decoder: any APIBodyDecoder) throws -> Self { Self() }
}

final class APIClientScopeTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    func testScopedProviderReceivesEndpointScopes() async throws {
        let recorder = ScopeRecorder()
        let mock = MockTransport { _ in okResponse(#"{"id":1,"name":"x"}"#) }
        let client = APIClientImpl(baseURL: baseURL, transport: mock, authTokenProvider: RecordingScopedToken(token: "tkn", recorder: recorder))
        _ = try await client.executeWithResponse(ScopedEndpointContract())
        XCTAssertEqual(recorder.scopes, ["endpoint.read"])
        XCTAssertEqual(mock.recordedRequests.first?.headers["authorization"], "Bearer tkn")
    }

    func testScopedProviderInheritsGroupScopes() async throws {
        let recorder = ScopeRecorder()
        let mock = MockTransport { _ in okResponse(#"{"id":1,"name":"x"}"#) }
        let client = APIClientImpl(baseURL: baseURL, transport: mock, authTokenProvider: RecordingScopedToken(token: "tkn", recorder: recorder))
        _ = try await client.executeWithResponse(GroupScopedContract())
        XCTAssertEqual(recorder.scopes, ["group.default"])
    }

    func testNonScopedProviderStillWorks() async throws {
        let mock = MockTransport { _ in okResponse(#"{"id":1,"name":"x"}"#) }
        let client = APIClientImpl(baseURL: baseURL, transport: mock, authTokenProvider: StaticToken(token: "plain"))
        _ = try await client.executeWithResponse(ScopedEndpointContract())
        XCTAssertEqual(mock.recordedRequests.first?.headers["authorization"], "Bearer plain")
    }
}
