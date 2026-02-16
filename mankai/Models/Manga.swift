//
//  Manga.swift
//  mankai
//
//  Created by Travis XU on 21/6/2025.
//

import Foundation

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

enum Status: UInt, Codable {
    case any = 0
    case onGoing = 1
    case ended = 2
}

struct Chapter: Codable {
    var id: String
    var title: String?
    var locked: Bool?
}

struct Manga: Identifiable, Codable {
    var id: String
    var title: String?
    var cover: String?
    var status: Status?
    var latestChapter: Chapter?

    var meta: String?

    init?(from any: Any) {
        guard let dict = any as? [String: Any],
              let id = dict["id"] as? String
        else {
            return nil
        }

        self.id = id
        title = dict["title"] as? String
        cover = dict["cover"] as? String
        meta = dict["meta"] as? String

        if let statusValue = dict["status"] {
            if let statusUInt = statusValue as? UInt {
                status = Status(rawValue: statusUInt)
            } else if let statusString = statusValue as? String,
                      let statusUInt = UInt(statusString)
            {
                status = Status(rawValue: statusUInt)
            } else {
                status = nil
            }
        } else {
            status = nil
        }

        if let chapterDict = dict["latestChapter"] as? [String: Any],
           let id = chapterDict["id"] as? String
        {
            latestChapter = Chapter(
                id: id,
                title: chapterDict["title"] as? String
            )
        } else {
            latestChapter = nil
        }
    }
}
