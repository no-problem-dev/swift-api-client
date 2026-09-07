import APIContract
import Foundation

/// What an `Output` type declares when its endpoint may answer with no body at all.
///
/// A response with no bytes cannot be decoded, and not because the type would have refused
/// it. Parsing runs first: the JSON parser reaches the end of the input before it reads
/// anything and throws, so `init(from:)` is never called and the type never gets to say it
/// would have been happy with nothing. Conforming is how a type says so in advance.
///
/// `EmptyOutput` conforms, so `typealias Output = EmptyOutput` — the usual spelling for a
/// delete — needs nothing further. `Optional` conforms too, so an endpoint that sometimes
/// answers with a body and sometimes with none can say `typealias Output = Thing?` and read
/// `nil` as "nothing came back". Conform your own type when it has such a value:
///
/// ```swift
/// struct Ack: EmptyBodyDecodable, Sendable {
///     static let emptyBody = Ack()
/// }
/// ```
///
/// An `Output` that does not conform fails such a response with
/// ``APIError/emptyResponseBody(statusCode:outputType:)``, rather than a decoding error —
/// nothing was mis-shaped, there was simply nothing there.
///
/// Only `Decodable` is required here, not `Sendable`, although every `Output` is both. A
/// conditional conformance cannot depend on a marker protocol, so requiring `Sendable`
/// here would cost `Optional` its conformance for nothing: the constraint on `Output`
/// already supplies it at the one place this protocol is consulted.
public protocol EmptyBodyDecodable: Decodable {
    /// The value that stands for a response that carried no body.
    static var emptyBody: Self { get }
}

/// The output of an endpoint that returns no body, which is this case exactly.
extension EmptyOutput: EmptyBodyDecodable {
    public static var emptyBody: EmptyOutput { EmptyOutput() }
}

/// `nil` already means "nothing came back", so an optional output needs no other spelling.
///
/// Note that this makes a body of literal `null` and no body at all arrive as the same
/// value. That is the point of declaring the output optional; an endpoint that has to tell
/// those apart wants two `Output` types, not one.
extension Optional: EmptyBodyDecodable where Wrapped: Decodable {
    public static var emptyBody: Self { nil }
}
