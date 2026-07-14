//
//  DetailedManga.swift
//  mankai
//
//  Created by Travis XU on 21/6/2025.
//

import Foundation

struct DetailedManga: Identifiable, Codable {
    var id: String
    var title: String?
    var cover: String?
    var status: Status?
    var readingDirection: ReadingDirection?
    var latestChapter: Chapter?
    var description: String?
    var updatedAt: Date?
    var authors: [String]
    var genres: [Genre]
    var chapters: [String: [Chapter]]
    var remarks: String?

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
        description = dict["description"] as? String
        meta = dict["meta"] as? String
        remarks = dict["remarks"] as? String

        // Parse status
        if let statusValue = dict["status"] {
            switch statusValue {
            case let status as Status:
                self.status = status
            case let statusInt as Int:
                status = Status(rawValue: statusInt)
            default:
                status = nil
            }
        } else {
            status = nil
        }

        if let chapterDict = dict["latestChapter"] as? [String: Any], let id = chapterDict["id"] as? String {
            latestChapter = Chapter(
                id: id,
                title: chapterDict["title"] as? String
            )
        } else {
            latestChapter = nil
        }

        if let readingDirectionValue = dict["readingDirection"] {
            switch readingDirectionValue {
            case let readingDirection as ReadingDirection:
                self.readingDirection = readingDirection
            case let readingDirectionInt as Int:
                readingDirection = ReadingDirection(rawValue: readingDirectionInt)
            default:
                readingDirection = nil
            }
        }

        if let updatedAtMilliseconds = dict["updatedAt"] as? Int64 {
            updatedAt = Date(
                timeIntervalSince1970: TimeInterval(updatedAtMilliseconds) / 1000.0
            )
        } else {
            updatedAt = nil
        }

        authors = dict["authors"] as? [String] ?? []

        // Parse genres
        if let genresValue = dict["genres"] {
            switch genresValue {
            case let genresArray as [Genre]:
                genres = genresArray
            case let genresStringArray as [String]:
                genres = genresStringArray.compactMap { Genre(rawValue: $0) }
            default:
                genres = []
            }
        } else {
            genres = []
        }

        if let chaptersDict = dict["chapters"] as? [String: Any] {
            var chapters: [String: [Chapter]] = [:]

            for (key, value) in chaptersDict {
                chapters[key] = []

                for value in value as? [Any] ?? [] {
                    if let chapterDict = value as? [String: Any], let id = chapterDict["id"] as? String {
                        let chapter = Chapter(
                            id: id,
                            title: chapterDict["title"] as? String
                        )
                        chapters[key]!.append(chapter)
                    }
                }
            }

            self.chapters = chapters
        } else {
            chapters = [:]
        }
    }

    init() {
        id = UUID().uuidString
        authors = []
        genres = []
        chapters = [String(localized: "serial"): [], String(localized: "extra"): [], String(localized: "volume"): []]
        status = .onGoing
    }

    enum CodingKeys: String, CodingKey {
        case id, title, cover, status, readingDirection, latestChapter, description, updatedAt, authors, genres,
             chapters, meta, remarks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        cover = try container.decodeIfPresent(String.self, forKey: .cover)
        status = try container.decodeIfPresent(Status.self, forKey: .status)
        readingDirection = try container.decodeIfPresent(ReadingDirection.self, forKey: .readingDirection)
        latestChapter = try container.decodeIfPresent(Chapter.self, forKey: .latestChapter)
        description = try container.decodeIfPresent(String.self, forKey: .description)

        if let updatedAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .updatedAt) {
            updatedAt = Date(
                timeIntervalSince1970: TimeInterval(updatedAtMilliseconds) / 1000.0
            )
        } else {
            updatedAt = nil
        }

        authors = try container.decodeIfPresent([String].self, forKey: .authors) ?? []
        genres = try container.decodeIfPresent([Genre].self, forKey: .genres) ?? []
        chapters =
            try container.decodeIfPresent([String: [Chapter]].self, forKey: .chapters) ?? [:]

        meta = try container.decodeIfPresent(String.self, forKey: .meta)
        remarks = try container.decodeIfPresent(String.self, forKey: .remarks)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(cover, forKey: .cover)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(readingDirection, forKey: .readingDirection)
        try container.encodeIfPresent(latestChapter, forKey: .latestChapter)
        try container.encodeIfPresent(description, forKey: .description)

        if let updatedAt = updatedAt {
            let milliseconds = Int64(updatedAt.timeIntervalSince1970 * 1000)
            try container.encode(milliseconds, forKey: .updatedAt)
        }

        try container.encode(authors, forKey: .authors)
        try container.encode(genres, forKey: .genres)
        try container.encode(chapters, forKey: .chapters)

        try container.encodeIfPresent(meta, forKey: .meta)
        try container.encodeIfPresent(remarks, forKey: .remarks)
    }

    func toManga() -> Manga {
        var mangaDict: [String: Any] = [
            "id": id,
        ]

        if let title = title {
            mangaDict["title"] = title
        }

        if let cover = cover {
            mangaDict["cover"] = cover
        }

        if let status = status {
            mangaDict["status"] = status.rawValue
        }

        if let latestChapter = latestChapter {
            var chapterDict: [String: Any] = ["id": latestChapter.id]
            if let title = latestChapter.title {
                chapterDict["title"] = title
            }
            if let locked = latestChapter.locked {
                chapterDict["locked"] = locked
            }
            mangaDict["latestChapter"] = chapterDict
        }

        if let meta = meta {
            mangaDict["meta"] = meta
        }

        return Manga(from: mangaDict)!
    }
}
