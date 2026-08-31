//
//  SftpBrowsablePluginModel.swift
//  mankai
//
//  Created by Travis XU on 31/8/2026.
//

import GRDB

struct SftpBrowsablePluginModel {
    var id: String
    var name: String?
    var host: String
    var port: Int
    var username: String
    var password: String
    var shouldSync: Bool

    static func createTable(_ db: Database) throws {
        try db.create(table: SftpBrowsablePluginModel.databaseTableName, ifNotExists: true) {
            $0.primaryKey("id", .text)

            $0.column("name", .text)
            $0.column("host", .text).notNull()
            $0.column("port", .integer).notNull()
            $0.column("username", .text).notNull()
            $0.column("password", .text).notNull()
            $0.column("shouldSync", .boolean).notNull()
        }
    }
}

extension SftpBrowsablePluginModel: TableRecord {
    static let databaseTableName = "sftpbrowsableplugin"
}

extension SftpBrowsablePluginModel: Codable, FetchableRecord, PersistableRecord {}
