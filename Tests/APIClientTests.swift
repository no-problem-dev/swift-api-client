import XCTest
import Foundation
@testable import APIClient
import APIContract
import HTTPTransport

// MARK: - APIEndpoint Tests

final class APIEndpointTests: XCTestCase {
    func testInitWithDefaults() {
        let endpoint = APIEndpoint(path: "/v1/users")
        XCTAssertEqual(endpoint.path, "/v1/users")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertNil(endpoint.headers)
        XCTAssertNil(endpoint.body)
        XCTAssertNil(endpoint.queryItems)
    }

    func testInitWithAllParameters() {
        let bodyData = Data("test".utf8)
        let endpoint = APIEndpoint(
            path: "/v1/users", method: .post,
            headers: ["X-Custom": "value"], body: bodyData,
            queryItems: [URLQueryItem(name: "page", value: "1")]
        )
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.headers?["X-Custom"], "value")
        XCTAssertEqual(endpoint.body, bodyData)
        XCTAssertEqual(endpoint.queryItems?.first?.value, "1")
    }
}

// MARK: - APIError Tests

final class APIErrorTests: XCTestCase {
    func testNetworkErrorDescription() {
        let error = APIError.networkError(NSError(domain: "T", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network unreachable"]))
        XCTAssertTrue(error.errorDescription?.contains("ネットワークエラー") ?? false)
    }
    func testInvalidURLDescription() { XCTAssertEqual(APIError.invalidURL.errorDescription, "無効なURLです") }
    func testUnauthorizedDescription() { XCTAssertEqual(APIError.unauthorized.errorDescription, "認証が必要です") }
    func testHTTPErrorDescription() { XCTAssertEqual(APIError.httpError(statusCode: 404, data: Data()).errorDescription, "HTTPエラー: 404") }
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

private struct StaticToken: AuthTokenProvider { let token: String?; func getToken() async throws -> String? { token } }

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

// MARK: - Scope propagation (ScopedAuthTokenProvider)

/// `getToken(scopes:)` に渡されたスコープを記録するスレッドセーフな箱。
private final class ScopeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _scopes: [String]?
    var scopes: [String]? { lock.lock(); defer { lock.unlock() }; return _scopes }
    func record(_ value: [String]) { lock.lock(); _scopes = value; lock.unlock() }
}

private struct RecordingScopedToken: ScopedAuthTokenProvider {
    let token: String?
    let recorder: ScopeRecorder
    func getToken(scopes: [String]) async throws -> String? {
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

/// エンドポイント固有スコープを持つ契約。
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

/// 固有スコープを宣言せずグループ既定を継承する契約。
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
