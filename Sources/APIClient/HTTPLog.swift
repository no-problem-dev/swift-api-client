import Foundation

/// One finished request, in the shape a console line or an analytics event needs.
///
/// Read these from `APIClientImpl.logs`. Every buffered call produces exactly one entry
/// whether it succeeded or not; SSE calls produce none.
///
/// Switch over the cases to send structured metrics, or `print(log)` to get the
/// ``description`` block while debugging.
public enum HTTPLog: Sendable {
    /// A 2xx response, with the body as received and before any decoding.
    case success(endpoint: APIEndpoint, statusCode: Int, data: Data)
    /// A non-2xx response, emitted whether or not the group's `decodeError` claimed it.
    ///
    /// So this is the reliable place to count failures: the thrown error may be your own
    /// type, and this entry is still here.
    case httpError(endpoint: APIEndpoint, statusCode: Int, data: Data)
    /// A 2xx body that would not decode, emitted immediately before ``APIError/decodingError(_:)`` is thrown.
    ///
    /// `error` is the `DecodingError`'s description, already flattened to a string so it
    /// can cross into a logging pipeline; `targetType` names the type that was expected;
    /// `data` is the body that failed. Nothing else keeps those bytes — if you drop this
    /// entry, the payload that caused the failure is gone.
    case decodingError(endpoint: APIEndpoint, error: String, data: Data, targetType: String)
}

extension HTTPLog: CustomStringConvertible {
    /// A multi-line block for a human reading a console, not a format to parse.
    ///
    /// JSON bodies are pretty-printed, other bodies appear as text, and bodies that are
    /// not UTF-8 appear as a byte count. Any body over 10 KB is replaced by its size,
    /// whichever case carries it — a 500 answering with a large HTML page is the one that
    /// most needs the cap, not the one least likely to hit it.
    public var description: String {
        switch self {
        case .success(let endpoint, let statusCode, let data):
            return formatSuccess(endpoint: endpoint, statusCode: statusCode, data: data)
        case .httpError(let endpoint, let statusCode, let data):
            return formatHTTPError(endpoint: endpoint, statusCode: statusCode, data: data)
        case .decodingError(let endpoint, let error, let data, let targetType):
            return formatDecodingError(endpoint: endpoint, error: error, data: data, targetType: targetType)
        }
    }

    private func formatSuccess(endpoint: APIEndpoint, statusCode: Int, data: Data) -> String {
        var output = """
        ✅ ========== API REQUEST SUCCESS ==========
        📍 Endpoint: \(endpoint.method.rawValue) \(endpoint.path)
        ✅ Status Code: \(statusCode)

        """

        output += "📄 Response Data:\n"
        output += Self.formatBody(data: data)

        output += "\n✅ ========== END REQUEST SUCCESS =========="
        return output
    }

    private func formatHTTPError(endpoint: APIEndpoint, statusCode: Int, data: Data) -> String {
        var output = """
        ❌ ========== HTTP ERROR ==========
        📍 Endpoint: \(endpoint.method.rawValue) \(endpoint.path)
        🚫 Status Code: \(statusCode)
        📄 Error Response:

        """
        output += Self.formatBody(data: data)
        output += "\n❌ ========== END HTTP ERROR =========="
        return output
    }

    private func formatDecodingError(endpoint: APIEndpoint, error: String, data: Data, targetType: String) -> String {
        var output = """
        ❌ ========== DECODE ERROR ==========
        📍 Endpoint: \(endpoint.method.rawValue) \(endpoint.path)
        🎯 Target Type: \(targetType)
        ❗ Error: \(error)

        📄 Response Data:

        """
        output += Self.formatBody(data: data)
        output += "\n❌ ========== END DECODE ERROR =========="
        return output
    }

    /// The largest body rendered in full. Above it only the size is printed, which also
    /// keeps a big payload from being materialised into a `String` twice on the way there.
    private static let bodyDisplayLimit = 10_000

    private static func formatBody(data: Data) -> String {
        guard data.count < bodyDisplayLimit else {
            return "\(data.count) bytes (too large to display)"
        }
        return formatJSON(data: data)
    }

    private static func formatJSON(data: Data) -> String {
        if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
           let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        } else if let rawString = String(data: data, encoding: .utf8) {
            return "Raw data: \(rawString)"
        } else {
            return "Unable to convert data to string. Data size: \(data.count) bytes"
        }
    }
}
