//
//  WebDavBrowsablePluginModel.swift
//  mankai
//
//  Created by Travis XU on 10/8/2026.
//

import GRDB

struct WebDavBrowsablePluginModel {
    var id: String
    var name: String?
    var baseURL: String
    var username: String?
    var password: String?
    var shouldSync: Bool

    static func createTable(_ db: Database) throws {
        try db.create(table: WebDavBrowsablePluginModel.databaseTableName, ifNotExists: true) {
            $0.primaryKey("id", .text)

            $0.column("name", .text)
            $0.column("baseURL", .text).notNull()
            $0.column("username", .text)
            $0.column("password", .text)
            $0.column("shouldSync", .boolean).notNull()
        }
    }
}

extension WebDavBrowsablePluginModel: TableRecord {
    static let databaseTableName = "webdavbrowsableplugin"
}

extension WebDavBrowsablePluginModel: Codable, FetchableRecord, PersistableRecord {}
