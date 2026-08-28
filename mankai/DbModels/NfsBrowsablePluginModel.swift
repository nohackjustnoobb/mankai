//
//  NfsBrowsablePluginModel.swift
//  mankai
//
//  Created by Travis XU on 28/8/2026.
//

import GRDB

struct NfsBrowsablePluginModel {
    var id: String
    var name: String?
    var host: String
    var export: String
    var shouldSync: Bool

    static func createTable(_ db: Database) throws {
        try db.create(table: NfsBrowsablePluginModel.databaseTableName, ifNotExists: true) {
            $0.primaryKey("id", .text)

            $0.column("name", .text)
            $0.column("host", .text).notNull()
            $0.column("export", .text).notNull()
            $0.column("shouldSync", .boolean).notNull()
        }
    }
}

extension NfsBrowsablePluginModel: TableRecord {
    static let databaseTableName = "nfsbrowsableplugin"
}

extension NfsBrowsablePluginModel: Codable, FetchableRecord, PersistableRecord {}
