//
//  SmbBrowsablePluginModel.swift
//  mankai
//
//  Created by Travis XU on 4/8/2026.
//

import GRDB

struct SmbBrowsablePluginModel {
    var id: String
    var name: String?
    var host: String
    var port: Int
    var share: String
    var username: String?
    var password: String?
    var shouldSync: Bool

    static func createTable(_ db: Database) throws {
        try db.create(table: SmbBrowsablePluginModel.databaseTableName, ifNotExists: true) {
            $0.primaryKey("id", .text)

            $0.column("name", .text)
            $0.column("host", .text).notNull()
            $0.column("port", .integer).notNull()
            $0.column("share", .text).notNull()
            $0.column("username", .text)
            $0.column("password", .text)
            $0.column("shouldSync", .boolean).notNull()
        }
    }
}

extension SmbBrowsablePluginModel: TableRecord {
    static let databaseTableName = "smbbrowsableplugin"
}

extension SmbBrowsablePluginModel: Codable, FetchableRecord, PersistableRecord {}
