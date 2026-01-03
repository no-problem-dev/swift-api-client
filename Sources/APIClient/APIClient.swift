@_exported import APIContract
import Foundation

/// HTTPベースのAPIクライアントプロトコル
public protocol APIClient: APIExecutable {
    func encode<T: Encodable>(_ value: T) throws -> Data
    var events: AsyncStream<HTTPEvent> { get }
    var logs: AsyncStream<HTTPLog> { get }
}
