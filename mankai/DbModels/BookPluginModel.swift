//
//  BookPluginModel.swift
//  mankai
//
//  Created by Travis XU on 13/7/2026.
//

import Foundation
import GRDB

struct BookPluginModel {
    var id: String
    var bookmarkData: Data

    static func createTable(_ db: Database) throws {
        try db.create(table: BookPluginModel.databaseTableName, ifNotExists: true) {
            $0.primaryKey("id", .text)

            $0.column("bookmarkData", .blob).notNull()
        }
    }
}

extension BookPluginModel: TableRecord {
    static let databaseTableName = "bookplugin"
}

extension BookPluginModel: Codable, FetchableRecord, PersistableRecord {}
