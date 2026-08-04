//
//  FsBrowsablePluginModel.swift
//  mankai
//
//  Created by Travis XU on 13/7/2026.
//

import Foundation
import GRDB

struct FsBrowsablePluginModel {
    var id: String
    var name: String?
    var bookmarkData: Data

    static func createTable(_ db: Database) throws {
        try db.create(table: FsBrowsablePluginModel.databaseTableName, ifNotExists: true) {
            $0.primaryKey("id", .text)

            $0.column("name", .text)
            $0.column("bookmarkData", .blob).notNull()
        }
    }
}

extension FsBrowsablePluginModel: TableRecord {
    static let databaseTableName = "fsbrowsableplugin"
}

extension FsBrowsablePluginModel: Codable, FetchableRecord, PersistableRecord {}
