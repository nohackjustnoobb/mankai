//
//  Manga.swift
//  mankai
//
//  Created by Travis XU on 21/6/2025.
//

import Foundation
import ReerCodable

enum Genre: String, Codable, CaseIterable {
    case all
    case action
    case romance
    case yuri
    case boysLove
    case otokonoko
    case schoolLife
    case adventure
    case harem
    case speculativeFiction
    case war
    case suspense
    case fanFiction
    case comedy
    case magic
    case horror
    case historical
    case sports
    case mature
    case mecha
}

@Codable
enum Status: Int {
    case any = 0
    case onGoing = 1
    case ended = 2
}

struct Chapter: Codable {
    var id: String
    var title: String?
    var locked: Bool?
}

@Codable
struct Manga: Identifiable {
    var id: String
    var title: String?
    var cover: String?
    var status: Status?
    var latestChapter: Chapter?

    var meta: String?

    init?(from any: Any) {
        guard let dict = any as? [String: Any],
            let decoded = try? Self.decoded(from: dict)
        else { return nil }
        self = decoded
    }
}
