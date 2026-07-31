//
//  DownloadMangaModel.swift
//  mankai
//
//  Created by Travis XU on 19/7/2025.
//

import Foundation
import GRDB

struct DownloadMangaModel {
    var pluginId: String
    var mangaId: String

    var id: String // pluginId+mangaId

    var title: String?
    var cover: String?
    var status: Int?
    var description: String?
    var updatedAt: Date?
    var authors: String
    var genres: String

    var latestChapter: String? // Chapter encoded in json
    var chapters: String? // ChapterGroup[] encoded as JSON

    var downloaded: Bool // if true, the manga is fully downloaded

    static func createTable(_ db: Database) throws {
        try db.create(table: DownloadMangaModel.databaseTableName, ifNotExists: true) {
            $0.column("pluginId", .text).notNull().indexed()
            $0.column("mangaId", .text).notNull().indexed()

            $0.primaryKey("id", .text)

            $0.column("title", .text)
            $0.column("cover", .text)
            $0.column("status", .integer)
            $0.column("description", .text)
            $0.column("updatedAt", .datetime)
            $0.column("authors", .text)
            $0.column("genres", .text)

            $0.column("latestChapter", .text)
            $0.column("chapters", .text)

            $0.column("downloaded", .boolean)
        }
    }
}

extension DownloadMangaModel: TableRecord {
    static let databaseTableName = "manga"

    static let chapters = hasMany(DownloadChapterModel.self)
}

extension DownloadMangaModel: Codable, FetchableRecord, PersistableRecord {
    var downloadChapters: QueryInterfaceRequest<DownloadChapterModel> {
        request(for: DownloadMangaModel.chapters)
    }
}
