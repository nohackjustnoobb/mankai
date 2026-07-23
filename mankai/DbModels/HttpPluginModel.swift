//
//  HttpPluginModel.swift
//  mankai
//
//  Created by Travis XU on 19/7/2025.
//

import GRDB

struct HttpPluginModel {
    var id: String
    var baseUrl: String
    var meta: String
    var configValues: String

    static func createTable(_ db: Database) throws {
        try db.create(table: HttpPluginModel.databaseTableName, ifNotExists: true) {
            $0.primaryKey("id", .text)

            $0.column("baseUrl", .text).notNull()
            $0.column("meta", .text).notNull()
            $0.column("configValues", .text).notNull()
        }
    }
}

extension HttpPluginModel: TableRecord {
    static let databaseTableName = "httpplugin"
}

extension HttpPluginModel: Codable, FetchableRecord, PersistableRecord {}
