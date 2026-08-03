//
//  FsBPMangaModel.swift
//  mankai
//
//  Created by Travis XU on 16/7/2026.
//

import GRDB

struct FsBPMangaModel {
    var mangaId: String
    var parserId: String
    var pluginId: String
    var path: String
    var info: String

    static func createTable(_ db: Database) throws {
        try db.create(table: FsBPMangaModel.databaseTableName, ifNotExists: true) {
            $0.primaryKey(["mangaId", "parserId", "pluginId"])

            $0.column("mangaId", .text).notNull()
            $0.column("parserId", .text).notNull()
            $0.column("pluginId", .text).notNull()
            $0.column("path", .text).notNull()
            $0.column("info", .text).notNull()
        }

        try db.create(
            index: "fsbpmanga_on_path_parserId_pluginId",
            on: FsBPMangaModel.databaseTableName,
            columns: ["path", "parserId", "pluginId"],
            ifNotExists: true
        )
    }
}

extension FsBPMangaModel: TableRecord {
    static let databaseTableName = "fsbpmanga"
}

extension FsBPMangaModel: Codable, FetchableRecord, PersistableRecord {}
