//
//  FlexibleDateCoding.swift
//  mankai
//
//  Created by Travis XU on 6/8/2025.
//

import Foundation
import ReerCodable

/// Encodes dates as millisecond timestamps and accepts timestamps or ISO-8601 strings when decoding.
struct FlexibleDateCoding: CodingCustomizable {
    typealias Value = Date

    static func decode(by decoder: any Decoder, keys: [String]) throws -> Date {
        guard let key = keys.first else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Missing date key"))
        }

        let codingKey = AnyCodingKey(key)
        let container = try decoder.container(keyedBy: AnyCodingKey.self)

        if let milliseconds = try? container.decode(Int64.self, forKey: codingKey) {
            return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
        }

        if let milliseconds = try? container.decode(Double.self, forKey: codingKey) {
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }

        let value = try container.decode(String.self, forKey: codingKey)
        guard let date = DateCodingStrategy.parseISO8601(value) else {
            throw DecodingError.dataCorruptedError(
                forKey: codingKey, in: container,
                debugDescription: "Expected an ISO-8601 date or a millisecond timestamp")
        }
        return date
    }

    static func encode(by encoder: any Encoder, key: String, value: Date) throws {
        try encoder.set(Int64(value.timeIntervalSince1970 * 1000), forKey: key)
    }
}
