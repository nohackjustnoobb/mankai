//
//  CbzParserModel.swift
//  mankai
//
//  Created by Travis XU on 16/7/2026.
//

import GRDB

struct CbzParserModel {
    var mangaId: String
    var pluginId: String
    var info: String

    static func createTable(_ db: Database) throws {
        try db.create(table: CbzParserModel.databaseTableName, ifNotExists: true) {
            $0.primaryKey(["mangaId", "pluginId"])

            $0.column("mangaId", .text).notNull()
            $0.column("pluginId", .text).notNull()
            $0.column("info", .text).notNull()
        }
    }
}

extension CbzParserModel: TableRecord {
    static let databaseTableName = "cbzparser"
}

extension CbzParserModel: Codable, FetchableRecord, PersistableRecord {}
