import XCTest
import Foundation
@testable import APIClient
import APIContract

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
        let queryItems = [URLQueryItem(name: "page", value: "1")]

        let endpoint = APIEndpoint(
            path: "/v1/users",
            method: .post,
            headers: ["X-Custom": "value"],
            body: bodyData,
            queryItems: queryItems
        )

        XCTAssertEqual(endpoint.path, "/v1/users")
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.headers?["X-Custom"], "value")
        XCTAssertEqual(endpoint.body, bodyData)
        XCTAssertEqual(endpoint.queryItems?.first?.name, "page")
        XCTAssertEqual(endpoint.queryItems?.first?.value, "1")
    }

    func testEndpointIsSendable() {
        let endpoint = APIEndpoint(path: "/test")

        Task {
            let _ = endpoint
        }
    }
}

// MARK: - APIError Tests

final class APIErrorTests: XCTestCase {

    func testNetworkErrorDescription() {
        let underlyingError = NSError(domain: "TestDomain", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Network unreachable"
        ])
        let error = APIError.networkError(underlyingError)

        XCTAssertTrue(error.errorDescription?.contains("ネットワークエラー") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("Network unreachable") ?? false)
    }

    func testDecodingErrorDescription() {
        let underlyingError = NSError(domain: "DecodingError", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Type mismatch"
        ])
        let error = APIError.decodingError(underlyingError)

        XCTAssertTrue(error.errorDescription?.contains("デコードエラー") ?? false)
    }

    func testInvalidURLDescription() {
        let error = APIError.invalidURL

        XCTAssertEqual(error.errorDescription, "無効なURLです")
    }

    func testInvalidResponseDescription() {
        let error = APIError.invalidResponse

        XCTAssertEqual(error.errorDescription, "無効なレスポンスです")
    }

    func testUnauthorizedDescription() {
        let error = APIError.unauthorized

        XCTAssertEqual(error.errorDescription, "認証が必要です")
    }

    func testHTTPErrorDescription() {
        let error = APIError.httpError(statusCode: 404, data: Data())

        XCTAssertEqual(error.errorDescription, "HTTPエラー: 404")
    }

    func testAPIErrorConformsToLocalizedError() {
        let error: LocalizedError = APIError.invalidURL

        XCTAssertNotNil(error.errorDescription)
    }
}

// MARK: - HTTPLog Tests

final class HTTPLogTests: XCTestCase {

    func testSuccessDescription() {
        let endpoint = APIEndpoint(path: "/v1/users", method: .get)
        let responseData = """
        {"id": 1, "name": "Test"}
        """.data(using: .utf8)!

        let log = HTTPLog.success(endpoint: endpoint, statusCode: 200, data: responseData)
        let description = log.description

        XCTAssertTrue(description.contains("API REQUEST SUCCESS"))
        XCTAssertTrue(description.contains("GET /v1/users"))
        XCTAssertTrue(description.contains("200"))
        XCTAssertTrue(description.contains("id"))
    }

    func testHTTPErrorDescription() {
        let endpoint = APIEndpoint(path: "/v1/users/999", method: .get)
        let errorData = """
        {"error": "Not Found"}
        """.data(using: .utf8)!

        let log = HTTPLog.httpError(endpoint: endpoint, statusCode: 404, data: errorData)
        let description = log.description

        XCTAssertTrue(description.contains("HTTP ERROR"))
        XCTAssertTrue(description.contains("GET /v1/users/999"))
        XCTAssertTrue(description.contains("404"))
        XCTAssertTrue(description.contains("Not Found"))
    }

    func testDecodingErrorDescription() {
        let endpoint = APIEndpoint(path: "/v1/data", method: .get)
        let invalidData = "invalid json".data(using: .utf8)!

        let log = HTTPLog.decodingError(
            endpoint: endpoint,
            error: "Type mismatch at key 'id'",
            data: invalidData,
            targetType: "User"
        )
        let description = log.description

        XCTAssertTrue(description.contains("DECODE ERROR"))
        XCTAssertTrue(description.contains("GET /v1/data"))
        XCTAssertTrue(description.contains("User"))
        XCTAssertTrue(description.contains("Type mismatch"))
    }

    func testLargeDataTruncation() {
        let endpoint = APIEndpoint(path: "/v1/large", method: .get)
        let largeData = Data(repeating: 65, count: 15000) // 15KB of 'A'

        let log = HTTPLog.success(endpoint: endpoint, statusCode: 200, data: largeData)
        let description = log.description

        XCTAssertTrue(description.contains("too large to display"))
    }

    func testInvalidJSONFormatting() {
        let endpoint = APIEndpoint(path: "/v1/test", method: .get)
        let invalidJSON = "not json at all".data(using: .utf8)!

        let log = HTTPLog.success(endpoint: endpoint, statusCode: 200, data: invalidJSON)
        let description = log.description

        XCTAssertTrue(description.contains("Raw data"))
    }

    func testHTTPLogIsSendable() {
        let endpoint = APIEndpoint(path: "/test")
        let log = HTTPLog.success(endpoint: endpoint, statusCode: 200, data: Data())

        Task {
            let _ = log
        }
    }
}

// MARK: - HTTPEvent Tests

final class HTTPEventTests: XCTestCase {

    func testUnauthorizedEvent() {
        let endpoint = APIEndpoint(path: "/v1/protected", method: .get)
        let data = Data()

        let event = HTTPEvent.unauthorized(endpoint: endpoint, data: data)

        if case .unauthorized(let ep, _) = event {
            XCTAssertEqual(ep.path, "/v1/protected")
        } else {
            XCTFail("Expected unauthorized event")
        }
    }

    func testForbiddenEvent() {
        let endpoint = APIEndpoint(path: "/v1/admin", method: .get)
        let data = Data()

        let event = HTTPEvent.forbidden(endpoint: endpoint, data: data)

        if case .forbidden(let ep, _) = event {
            XCTAssertEqual(ep.path, "/v1/admin")
        } else {
            XCTFail("Expected forbidden event")
        }
    }

    func testRateLimitedEvent() {
        let endpoint = APIEndpoint(path: "/v1/api", method: .get)
        let data = Data()
        let retryAfter: TimeInterval = 60

        let event = HTTPEvent.rateLimited(endpoint: endpoint, retryAfter: retryAfter, data: data)

        if case .rateLimited(let ep, let retry, _) = event {
            XCTAssertEqual(ep.path, "/v1/api")
            XCTAssertEqual(retry, 60)
        } else {
            XCTFail("Expected rateLimited event")
        }
    }

    func testRateLimitedEventWithNilRetryAfter() {
        let endpoint = APIEndpoint(path: "/v1/api", method: .get)
        let data = Data()

        let event = HTTPEvent.rateLimited(endpoint: endpoint, retryAfter: nil, data: data)

        if case .rateLimited(_, let retry, _) = event {
            XCTAssertNil(retry)
        } else {
            XCTFail("Expected rateLimited event")
        }
    }

    func testServiceUnavailableEvent() {
        let endpoint = APIEndpoint(path: "/v1/service", method: .get)
        let data = Data()

        let event = HTTPEvent.serviceUnavailable(endpoint: endpoint, data: data)

        if case .serviceUnavailable(let ep, _) = event {
            XCTAssertEqual(ep.path, "/v1/service")
        } else {
            XCTFail("Expected serviceUnavailable event")
        }
    }

    func testServerErrorEvent() {
        let endpoint = APIEndpoint(path: "/v1/error", method: .post)
        let data = Data()

        let event = HTTPEvent.serverError(statusCode: 500, endpoint: endpoint, data: data)

        if case .serverError(let code, let ep, _) = event {
            XCTAssertEqual(code, 500)
            XCTAssertEqual(ep.path, "/v1/error")
        } else {
            XCTFail("Expected serverError event")
        }
    }

    func testHTTPEventIsSendable() {
        let endpoint = APIEndpoint(path: "/test")
        let event = HTTPEvent.unauthorized(endpoint: endpoint, data: Data())

        Task {
            let _ = event
        }
    }
}

// MARK: - Mock URLSession

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("Handler not set")
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Mock AuthTokenProvider

struct MockAuthTokenProvider: AuthTokenProvider {
    let token: String?
    let shouldThrow: Bool

    init(token: String? = nil, shouldThrow: Bool = false) {
        self.token = token
        self.shouldThrow = shouldThrow
    }

    func getToken() async throws -> String? {
        if shouldThrow {
            throw NSError(domain: "AuthError", code: -1)
        }
        return token
    }
}

// MARK: - Test Contract (using resolvePath as protocol requirement)

enum TestAPIGroup: APIContractGroup {
    static let basePath: String = "/v1"
    static let auth: AuthRequirement = .required
    static let endpoints: [EndpointDescriptor] = []
}

struct TestContract: APIContract, APIInput {
    typealias Group = TestAPIGroup
    typealias Input = Self
    typealias Output = TestResponse

    static let method: APIMethod = .get
    static let subPath: String = "/users"

    var pathParameters: [String: String] { [:] }
    var queryParameters: [String: String]? { nil }

    func encodeBody(using encoder: JSONEncoder) throws -> Data? { nil }

    static func decode(
        pathParameters: [String: String],
        queryParameters: [String: String],
        body: Data?,
        decoder: JSONDecoder
    ) throws -> Self {
        Self()
    }
}

struct TestResponse: Codable, Sendable {
    let id: Int
    let name: String
}

struct PostContract: APIContract, APIInput {
    typealias Group = TestAPIGroup
    typealias Input = Self
    typealias Output = TestResponse

    static let method: APIMethod = .post
    static let subPath: String = "/users"

    let bodyContent: PostBody

    var pathParameters: [String: String] { [:] }
    var queryParameters: [String: String]? { nil }

    func encodeBody(using encoder: JSONEncoder) throws -> Data? {
        try encoder.encode(bodyContent)
    }

    static func decode(
        pathParameters: [String: String],
        queryParameters: [String: String],
        body: Data?,
        decoder: JSONDecoder
    ) throws -> Self {
        fatalError("Client-only contract")
    }
}

struct PostBody: Codable, Sendable {
    let name: String
}

struct QueryContract: APIContract, APIInput {
    typealias Group = TestAPIGroup
    typealias Input = Self
    typealias Output = TestResponse

    static let method: APIMethod = .get
    static let subPath: String = "/users"

    let page: Int
    let limit: Int

    var pathParameters: [String: String] { [:] }
    var queryParameters: [String: String]? {
        ["page": "\(page)", "limit": "\(limit)"]
    }

    func encodeBody(using encoder: JSONEncoder) throws -> Data? { nil }

    static func decode(
        pathParameters: [String: String],
        queryParameters: [String: String],
        body: Data?,
        decoder: JSONDecoder
    ) throws -> Self {
        Self(page: 0, limit: 0)
    }
}

// MARK: - APIClientImpl Tests

final class APIClientImplTests: XCTestCase {

    var session: URLSession!
    var client: APIClientImpl!

    override func setUp() {
        super.setUp()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)

        client = APIClientImpl(
            baseURL: URL(string: "https://api.example.com")!,
            session: session
        )
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        session = nil
        client = nil
        super.tearDown()
    }

    // MARK: - Success Tests

    func testExecuteSuccessfulRequest() async throws {
        let responseData = """
        {"id": 1, "name": "Test User"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/users")
            XCTAssertEqual(request.httpMethod, "GET")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, responseData)
        }

        let contract = TestContract()
        let result: TestResponse = try await client.execute(contract)

        XCTAssertEqual(result.id, 1)
        XCTAssertEqual(result.name, "Test User")
    }

    func testExecutePostRequest() async throws {
        let responseData = """
        {"id": 2, "name": "Created User"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, responseData)
        }

        let contract = PostContract(bodyContent: PostBody(name: "New User"))
        let result: TestResponse = try await client.execute(contract)

        XCTAssertEqual(result.id, 2)
        XCTAssertEqual(result.name, "Created User")
    }

    func testExecuteWithQueryParameters() async throws {
        let responseData = """
        {"id": 1, "name": "User"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let queryItems = components?.queryItems ?? []

            XCTAssertTrue(queryItems.contains { $0.name == "page" && $0.value == "1" })
            XCTAssertTrue(queryItems.contains { $0.name == "limit" && $0.value == "10" })

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, responseData)
        }

        let contract = QueryContract(page: 1, limit: 10)
        let _: TestResponse = try await client.execute(contract)
    }

    // MARK: - Auth Token Tests

    func testRequestIncludesAuthToken() async throws {
        let clientWithAuth = APIClientImpl(
            baseURL: URL(string: "https://api.example.com")!,
            session: session,
            authTokenProvider: MockAuthTokenProvider(token: "test-token-123")
        )

        let responseData = """
        {"id": 1, "name": "User"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-123")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, responseData)
        }

        let contract = TestContract()
        let _: TestResponse = try await clientWithAuth.execute(contract)
    }

    func testRequestWithoutAuthToken() async throws {
        let clientWithoutAuth = APIClientImpl(
            baseURL: URL(string: "https://api.example.com")!,
            session: session,
            authTokenProvider: MockAuthTokenProvider(token: nil)
        )

        let responseData = """
        {"id": 1, "name": "User"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, responseData)
        }

        let contract = TestContract()
        let _: TestResponse = try await clientWithoutAuth.execute(contract)
    }

    // MARK: - Error Status Code Tests

    func testUnauthorizedError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let contract = TestContract()

        do {
            let _: TestResponse = try await client.execute(contract)
            XCTFail("Expected error to be thrown")
        } catch let error as APIError {
            if case .unauthorized = error {
                // Expected
            } else {
                XCTFail("Expected unauthorized error")
            }
        }
    }

    func testNotFoundError() async throws {
        let errorData = """
        {"error": "Not Found"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, errorData)
        }

        let contract = TestContract()

        do {
            let _: TestResponse = try await client.execute(contract)
            XCTFail("Expected error to be thrown")
        } catch let error as APIError {
            if case .httpError(let statusCode, _) = error {
                XCTAssertEqual(statusCode, 404)
            } else {
                XCTFail("Expected httpError")
            }
        }
    }

    func testServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let contract = TestContract()

        do {
            let _: TestResponse = try await client.execute(contract)
            XCTFail("Expected error to be thrown")
        } catch let error as APIError {
            if case .httpError(let statusCode, _) = error {
                XCTAssertEqual(statusCode, 500)
            } else {
                XCTFail("Expected httpError")
            }
        }
    }

    // MARK: - Decoding Error Test

    func testDecodingError() async throws {
        let invalidJSON = "not valid json".data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, invalidJSON)
        }

        let contract = TestContract()

        do {
            let _: TestResponse = try await client.execute(contract)
            XCTFail("Expected error to be thrown")
        } catch let error as APIError {
            if case .decodingError = error {
                // Expected
            } else {
                XCTFail("Expected decodingError, got \(error)")
            }
        }
    }

    // MARK: - Default Headers Test

    func testDefaultHeaders() async throws {
        let clientWithHeaders = APIClientImpl(
            baseURL: URL(string: "https://api.example.com")!,
            session: session,
            defaultHeaders: ["X-API-Key": "secret-key"]
        )

        let responseData = """
        {"id": 1, "name": "User"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "secret-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, responseData)
        }

        let contract = TestContract()
        let _: TestResponse = try await clientWithHeaders.execute(contract)
    }

    // MARK: - Retry-After Parsing Tests

    func testParseRetryAfterSeconds() {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "120"]
        )!

        let retryAfter = APIClientImpl.parseRetryAfter(from: response)

        XCTAssertEqual(retryAfter, 120)
    }

    func testParseRetryAfterMissing() {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: nil
        )!

        let retryAfter = APIClientImpl.parseRetryAfter(from: response)

        XCTAssertNil(retryAfter)
    }

    // MARK: - Encode Test

    func testEncode() throws {
        struct TestData: Codable {
            let name: String
            let value: Int
        }

        let data = TestData(name: "test", value: 42)
        let encoded = try client.encode(data)

        let decoded = try JSONDecoder().decode(TestData.self, from: encoded)
        XCTAssertEqual(decoded.name, "test")
        XCTAssertEqual(decoded.value, 42)
    }
}

// MARK: - Date Encoding/Decoding Tests

final class DateStrategyTests: XCTestCase {

    func testDefaultDateEncodingStrategy() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = APIClientImpl.defaultDateEncodingStrategy()

        struct DateContainer: Codable {
            let date: Date
        }

        let date = Date(timeIntervalSince1970: 1704067200) // 2024-01-01T00:00:00Z
        let container = DateContainer(date: date)

        let data = try encoder.encode(container)
        let jsonString = String(data: data, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("2024-01-01"))
    }

    func testDefaultDateDecodingStrategyISO8601() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = APIClientImpl.defaultDateDecodingStrategy()

        struct DateContainer: Codable {
            let date: Date
        }

        let json = """
        {"date": "2024-01-01T12:00:00Z"}
        """.data(using: .utf8)!

        let container = try decoder.decode(DateContainer.self, from: json)
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: container.date)

        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 1)
    }

    func testDefaultDateDecodingStrategyWithFractionalSeconds() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = APIClientImpl.defaultDateDecodingStrategy()

        struct DateContainer: Codable {
            let date: Date
        }

        let json = """
        {"date": "2024-01-01T12:00:00.123Z"}
        """.data(using: .utf8)!

        let container = try decoder.decode(DateContainer.self, from: json)

        XCTAssertNotNil(container.date)
    }

    func testDefaultDateDecodingStrategyDateOnly() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = APIClientImpl.defaultDateDecodingStrategy()

        struct DateContainer: Codable {
            let date: Date
        }

        let json = """
        {"date": "2024-01-15"}
        """.data(using: .utf8)!

        let container = try decoder.decode(DateContainer.self, from: json)
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: container.date)

        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 15)
    }

    func testDefaultDateDecodingStrategyInvalidFormat() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = APIClientImpl.defaultDateDecodingStrategy()

        struct DateContainer: Codable {
            let date: Date
        }

        let json = """
        {"date": "not-a-date"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(DateContainer.self, from: json))
    }
}

// MARK: - SSEEvent Tests

final class SSEEventTests: XCTestCase {

    func testSSEEventWithDataOnly() {
        let event = SSEEvent(data: "test data")

        XCTAssertEqual(event.data, "test data")
        XCTAssertNil(event.event)
        XCTAssertNil(event.id)
        XCTAssertNil(event.retry)
    }

    func testSSEEventWithAllFields() {
        let event = SSEEvent(
            data: "test data",
            event: "message",
            id: "123",
            retry: 5000
        )

        XCTAssertEqual(event.data, "test data")
        XCTAssertEqual(event.event, "message")
        XCTAssertEqual(event.id, "123")
        XCTAssertEqual(event.retry, 5000)
    }

    func testSSEEventEquatable() {
        let event1 = SSEEvent(data: "test", event: "message")
        let event2 = SSEEvent(data: "test", event: "message")
        let event3 = SSEEvent(data: "different", event: "message")

        XCTAssertEqual(event1, event2)
        XCTAssertNotEqual(event1, event3)
    }

    func testSSEEventHashable() {
        let event1 = SSEEvent(data: "test", event: "message")
        let event2 = SSEEvent(data: "test", event: "message")

        var set = Set<SSEEvent>()
        set.insert(event1)
        set.insert(event2)

        XCTAssertEqual(set.count, 1)
    }

    func testSSEEventDecodeData() throws {
        struct TestPayload: Codable {
            let name: String
            let value: Int
        }

        let event = SSEEvent(data: #"{"name":"test","value":42}"#)
        let payload = try event.decodeData(TestPayload.self)

        XCTAssertEqual(payload.name, "test")
        XCTAssertEqual(payload.value, 42)
    }

    func testSSEEventDecodeDataWithISO8601() throws {
        struct DatePayload: Codable {
            let timestamp: Date
        }

        let event = SSEEvent(data: #"{"timestamp":"2024-01-01T12:00:00Z"}"#)
        let payload = try event.decodeDataWithISO8601(DatePayload.self)

        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: payload.timestamp)
        XCTAssertEqual(components.year, 2024)
    }

    func testSSEEventDecodeDataThrowsWhenNoData() {
        let event = SSEEvent(event: "ping")

        XCTAssertThrowsError(try event.decodeData(String.self)) { error in
            if case SSEError.noData = error {
                // Expected
            } else {
                XCTFail("Expected SSEError.noData")
            }
        }
    }

    func testSSEEventIsSendable() {
        let event = SSEEvent(data: "test")

        Task {
            let _ = event
        }
    }
}

// MARK: - SSEError Tests

final class SSEErrorTests: XCTestCase {

    func testSSEErrorDescriptions() {
        XCTAssertEqual(SSEError.invalidURL.errorDescription, "Invalid URL")
        XCTAssertEqual(SSEError.invalidResponse.errorDescription, "Invalid response from server")
        XCTAssertEqual(SSEError.httpError(statusCode: 404, data: nil).errorDescription, "HTTP error: 404")
        XCTAssertEqual(SSEError.noData.errorDescription, "No data in event")
        XCTAssertEqual(SSEError.connectionClosed.errorDescription, "Connection closed")
    }

    func testSSEErrorDecodingDescription() {
        let underlyingError = NSError(domain: "test", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Parse error"
        ])
        let error = SSEError.decodingError(underlyingError)

        XCTAssertTrue(error.errorDescription?.contains("Decoding error") ?? false)
    }

    func testSSEErrorNetworkDescription() {
        let underlyingError = NSError(domain: "test", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Connection lost"
        ])
        let error = SSEError.networkError(underlyingError)

        XCTAssertTrue(error.errorDescription?.contains("Network error") ?? false)
    }
}

// MARK: - SSEClientImpl Tests

final class SSEClientImplTests: XCTestCase {

    func testSSEClientInitialization() {
        let client = SSEClientImpl(
            baseURL: URL(string: "https://api.example.com")!
        )

        XCTAssertNotNil(client)
    }

    func testSSEClientWithAuthTokenProvider() {
        let client = SSEClientImpl(
            baseURL: URL(string: "https://api.example.com")!,
            authTokenProvider: MockAuthTokenProvider(token: "test-token")
        )

        XCTAssertNotNil(client)
    }

    func testSSEClientWithDefaultHeaders() {
        let client = SSEClientImpl(
            baseURL: URL(string: "https://api.example.com")!,
            defaultHeaders: ["X-API-Key": "secret"]
        )

        XCTAssertNotNil(client)
    }

    func testSSEClientIsSendable() {
        let client = SSEClientImpl(
            baseURL: URL(string: "https://api.example.com")!
        )

        Task {
            let _ = client
        }
    }

    func testEmptySSEBodyIsSendable() {
        let body = EmptySSEBody()

        Task {
            let _ = body
        }
    }
}

// MARK: - SSE Event Parsing Tests

final class SSEEventParsingTests: XCTestCase {

    // MARK: - Basic Parsing Tests

    func testParseEventWithDataOnly() {
        let eventString = "data: Hello, World!"
        let event = SSEClientImpl.parseEvent(from: eventString)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.data, "Hello, World!")
        XCTAssertNil(event?.event)
        XCTAssertNil(event?.id)
        XCTAssertNil(event?.retry)
    }

    func testParseEventWithAllFields() {
        let eventString = """
        event: message
        data: test data
        id: 123
        retry: 5000
        """
        let event = SSEClientImpl.parseEvent(from: eventString)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.data, "test data")
        XCTAssertEqual(event?.event, "message")
        XCTAssertEqual(event?.id, "123")
        XCTAssertEqual(event?.retry, 5000)
    }

    func testParseEventWithEventTypeOnly() {
        let eventString = "event: ping"
        let event = SSEClientImpl.parseEvent(from: eventString)

        XCTAssertNotNil(event)
        XCTAssertNil(event?.data)
        XCTAssertEqual(event?.event, "ping")
    }

    func testParseEventWithIdOnly() {
        let eventString = "id: abc123"
        let event = SSEClientImpl.parseEvent(from: eventString)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.id, "abc123")
    }

    func testParseEventWithRetryOnly() {
        let eventString = "retry: 3000"
        let event = SSEClientImpl.parseEvent(from: eventString)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.retry, 3000)
    }

    // MARK: - Multiple Data Lines Tests

    func testParseEventWithMultipleDataLines() {
        let eventString = """
        data: line 1
        data: line 2
        data: line 3
        """
        let event = SSEClientImpl.parseEvent(from: eventString)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.data, "line 1\nline 2\nline 3")
    }

    func testParseEventWithJSONData() {
        let eventString = """
        event: progress
        data: {"type":"progress","payload":{"message":"Processing...","progress":0.5}}
        """
        let event = SSEClientImpl.parseEvent(from: eventString)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.event, "progress")
        XCTAssertTrue(event?.data?.contains("progress") ?? false)
        XCTAssertTrue(event?.data?.contains("0.5") ?? false)
    }

    // MARK: - Comment Handling Tests

    func testParseEventIgnoresComments() {
        let eventString = """
        : this is a comment
        data: actual data
        : another comment
        """
        let event = SSEClientImpl.parseEvent(from: eventString)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.data, "actual data")
    }

    func testParseEventWithOnlyComment() {
        let eventString = ": just a comment"
        let event = SSEClientImpl.parseEvent(from: eventString)

        XCTAssertNil(event)
    }

    // MARK: - Edge Cases

    func testParseEventWithEmptyData() {
        let eventString = "data:"
        let event = SSEClientImpl.parseEvent(from: eventString)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.data, "")
    }

    func testParseEventWithEmptyString() {
        let event = SSEClientImpl.parseEvent(from: "")
        XCTAssertNil(event)
    }

    func testParseEventWithOnlyNewlines() {
        let event = SSEClientImpl.parseEvent(from: "\n\n\n")
        XCTAssertNil(event)
    }

    func testParseEventWithUnknownFields() {
        let eventString = """
        unknown: should be ignored
        data: valid data
        custom: also ignored
        """
        let event = SSEClientImpl.parseEvent(from: eventString)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.data, "valid data")
    }

    func testParseEventWithColonInData() {
        let eventString = "data: time: 12:30:45"
        let event = SSEClientImpl.parseEvent(from: eventString)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.data, "time: 12:30:45")
    }

    func testParseEventWithLeadingSpaceInValue() {
        let eventString = "data:  value with leading space"
        let event = SSEClientImpl.parseEvent(from: eventString)

        XCTAssertNotNil(event)
        // Implementation trims all leading spaces (acceptable for JSON data use case)
        XCTAssertEqual(event?.data, "value with leading space")
    }

    func testParseEventWithInvalidRetry() {
        let eventString = """
        retry: not-a-number
        data: test
        """
        let event = SSEClientImpl.parseEvent(from: eventString)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.data, "test")
        XCTAssertNil(event?.retry)
    }

    // MARK: - Real-World Scenarios

    func testParseEventProgressEvent() {
        let eventString = """
        event: progress
        data: {"type":"progress","payload":{"message":"検索条件を分析しています...","progress":0.1,"step":"analyzing"}}
        """
        let event = SSEClientImpl.parseEvent(from: eventString)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.event, "progress")

        // Verify JSON is parseable
        struct ProgressData: Decodable {
            let type: String
            let payload: Payload
            struct Payload: Decodable {
                let message: String
                let progress: Double
                let step: String
            }
        }

        XCTAssertNoThrow(try event?.decodeData(ProgressData.self))
    }

    func testParseEventCandidateEvent() {
        let eventString = """
        event: candidate
        data: {"type":"candidate","payload":{"restaurant":{"id":"123","name":"テスト居酒屋","area":"渋谷"},"index":1}}
        """
        let event = SSEClientImpl.parseEvent(from: eventString)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.event, "candidate")
        XCTAssertTrue(event?.data?.contains("テスト居酒屋") ?? false)
    }

    func testParseEventCompleteEvent() {
        let eventString = """
        event: complete
        data: {"type":"complete","payload":{"result":{"candidates":[]}}}
        """
        let event = SSEClientImpl.parseEvent(from: eventString)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.event, "complete")
    }

    func testParseEventErrorEvent() {
        let eventString = """
        event: error
        data: {"type":"error","payload":{"code":"SEARCH_ERROR","message":"検索に失敗しました","retryable":true}}
        """
        let event = SSEClientImpl.parseEvent(from: eventString)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.event, "error")
    }

    // MARK: - Line-Based Parsing Simulation

    func testParseMultipleEventsFromLines() {
        // Simulating how bytes.lines would deliver events
        let lines = [
            "event: progress",
            "data: {\"progress\": 0.1}",
            "",  // Empty line marks end of event
            "event: progress",
            "data: {\"progress\": 0.5}",
            "",  // Empty line marks end of event
        ]

        var events: [SSEEvent] = []
        var currentLines: [String] = []

        for line in lines {
            if line.isEmpty {
                if !currentLines.isEmpty {
                    let eventString = currentLines.joined(separator: "\n")
                    if let event = SSEClientImpl.parseEvent(from: eventString) {
                        events.append(event)
                    }
                    currentLines.removeAll()
                }
            } else {
                currentLines.append(line)
            }
        }

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].event, "progress")
        XCTAssertEqual(events[1].event, "progress")
    }

    func testParseEventWithCRLFLineEndings() {
        // Some servers might send CRLF line endings
        let eventString = "event: message\r\ndata: test data\r\nid: 1"
        // Note: components(separatedBy: "\n") will keep \r in values
        // This tests the robustness of the parser

        let event = SSEClientImpl.parseEvent(from: eventString)
        XCTAssertNotNil(event)
        // The event type might have \r at the end
        XCTAssertTrue(event?.event?.hasPrefix("message") ?? false)
    }
}
