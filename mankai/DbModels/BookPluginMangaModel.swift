//
//  BookPluginMangaModel.swift
//  mankai
//
//  Created by Travis XU on 16/7/2026.
//

import GRDB

struct BookPluginMangaModel {
    var mangaId: String
    var parserId: String
    var pluginId: String
    var info: String

    static func createTable(_ db: Database) throws {
        try db.create(table: BookPluginMangaModel.databaseTableName, ifNotExists: true) {
            $0.primaryKey(["mangaId", "parserId", "pluginId"])

            $0.column("mangaId", .text).notNull()
            $0.column("parserId", .text).notNull()
            $0.column("pluginId", .text).notNull()
            $0.column("info", .text).notNull()
        }
    }
}

extension BookPluginMangaModel: TableRecord {
    static let databaseTableName = "bookpluginmanga"
}

extension BookPluginMangaModel: Codable, FetchableRecord, PersistableRecord {}
