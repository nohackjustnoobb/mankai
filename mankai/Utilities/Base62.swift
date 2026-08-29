//
//  Base62.swift
//  mankai
//
//  Created by Travis XU on 13/8/2026.
//

import Foundation

enum Base62 {
    private static let alphabet = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)

    private static let digitValues: [UInt8: UInt8] = Dictionary(
        uniqueKeysWithValues: alphabet.enumerated()
            .map { (offset, character) in (character, UInt8(offset)) })

    static func encode(_ value: String) -> String {
        var bytes = Array(value.utf8)
        guard !bytes.isEmpty else { return "" }

        let leadingZeroCount = bytes.prefix { $0 == 0 }.count
        var firstNonZeroIndex = leadingZeroCount
        var encoded: [UInt8] = []

        while firstNonZeroIndex < bytes.count {
            var remainder = 0

            for index in firstNonZeroIndex..<bytes.count {
                let accumulator = remainder * 256 + Int(bytes[index])
                bytes[index] = UInt8(accumulator / 62)
                remainder = accumulator % 62
            }

            encoded.append(alphabet[remainder])

            while firstNonZeroIndex < bytes.count && bytes[firstNonZeroIndex] == 0 {
                firstNonZeroIndex += 1
            }
        }

        encoded.append(contentsOf: repeatElement(alphabet[0], count: leadingZeroCount))
        return String(decoding: encoded.reversed(), as: UTF8.self)
    }

    static func decode(_ value: String) -> String? {
        let encoded = Array(value.utf8)
        guard !encoded.isEmpty else { return nil }

        var digits: [UInt8] = []
        digits.reserveCapacity(encoded.count)

        for character in encoded {
            guard let digit = digitValues[character] else { return nil }
            digits.append(digit)
        }

        let leadingZeroCount = digits.prefix { $0 == 0 }.count
        var firstNonZeroIndex = leadingZeroCount
        var decoded: [UInt8] = []

        while firstNonZeroIndex < digits.count {
            var remainder = 0

            for index in firstNonZeroIndex..<digits.count {
                let accumulator = remainder * 62 + Int(digits[index])
                digits[index] = UInt8(accumulator / 256)
                remainder = accumulator % 256
            }

            decoded.append(UInt8(remainder))

            while firstNonZeroIndex < digits.count && digits[firstNonZeroIndex] == 0 {
                firstNonZeroIndex += 1
            }
        }

        decoded.append(contentsOf: repeatElement(0, count: leadingZeroCount))
        return String(bytes: decoded.reversed(), encoding: .utf8)
    }
}
