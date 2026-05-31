import APIContract
import Foundation
import JSONParsing
import StructuredDataCore

// The body codec is swift-structured-data internally; this is hidden from
// callers, who only ever see `executeWithResponse`/`execute`. swift-structured-data's
// coders already match the seam shape, so conformance is free.
extension StructuredEncoder: @retroactive APIBodyEncoder {}
extension StructuredDecoder: @retroactive APIBodyDecoder {}

enum BodyCoding {
    static func encoder(keyStrategy: EncodingOptions.KeyStrategy, dateStrategy: DateCodingStrategy) -> any APIBodyEncoder {
        StructuredEncoder(
            serializer: JSONSerializer(),
            options: EncodingOptions(keyStrategy: keyStrategy, dateStrategy: dateStrategy)
        )
    }

    static func decoder(keyStrategy: DecodingOptions.KeyStrategy, dateStrategy: DateCodingStrategy) -> any APIBodyDecoder {
        StructuredDecoder(
            parser: JSONParser(),
            options: DecodingOptions(keyStrategy: keyStrategy, dateStrategy: dateStrategy)
        )
    }
}
