//
//  OpdsBrowsablePluginModel.swift
//  mankai
//
//  Created by Travis XU on 19/8/2026.
//

import GRDB

struct OpdsBrowsablePluginModel {
    var id: String
    var name: String?
    var catalogURL: String
    var username: String?
    var password: String?
    var shouldSync: Bool

    static func createTable(_ db: Database) throws {
        try db.create(table: OpdsBrowsablePluginModel.databaseTableName, ifNotExists: true) {
            $0.primaryKey("id", .text)

            $0.column("name", .text)
            $0.column("catalogURL", .text).notNull()
            $0.column("username", .text)
            $0.column("password", .text)
            $0.column("shouldSync", .boolean).notNull()
        }
    }
}

extension OpdsBrowsablePluginModel: TableRecord {
    static let databaseTableName = "opdsbrowsableplugin"
}

extension OpdsBrowsablePluginModel: Codable, FetchableRecord, PersistableRecord {}
