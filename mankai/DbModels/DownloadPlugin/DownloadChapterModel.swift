//
//  DownloadChapterModel.swift
//  mankai
//
//  Created by Travis XU on 19/7/2025.
//

import Foundation
import GRDB

struct DownloadChapterModel {
    var mangaId: String // pluginId+mangaId
    var chapterId: String
    var urls: String // encoded by inserting "|" between urls

    var downloaded: Bool // if true, the chapter is fully downloaded

    static func createTable(_ db: Database) throws {
        try db.create(table: DownloadChapterModel.databaseTableName, ifNotExists: true) {
            $0.primaryKey(["mangaId", "chapterId"])

            $0.column("mangaId", .text).notNull()
            $0.column("chapterId", .text).notNull()
            $0.column("urls", .text).notNull()

            $0.column("downloaded", .boolean)

            $0.foreignKey(
                ["mangaId"], references: DownloadMangaModel.databaseTableName, onDelete: .cascade
            )
        }
    }
}

extension DownloadChapterModel: TableRecord {
    static let databaseTableName = "chapter"

    static let manga = belongsTo(DownloadMangaModel.self)
}

extension DownloadChapterModel: Codable, FetchableRecord, PersistableRecord {
    var manga: QueryInterfaceRequest<DownloadMangaModel> {
        request(for: DownloadChapterModel.manga)
    }
}
