//
//  JsRuntimeKvPairModel.swift
//  mankai
//
//  Created by Travis XU on 31/1/2026.
//

import GRDB

struct JsRuntimeKvPairModel {
    var pluginId: String
    var key: String
    var value: String

    static func createTable(_ db: Database) throws {
        try db.create(table: JsRuntimeKvPairModel.databaseTableName, ifNotExists: true) {
            $0.primaryKey(["pluginId", "key"])

            $0.column("pluginId", .text).notNull()
            $0.column("key", .text).notNull()
            $0.column("value", .text).notNull()

            $0.foreignKey(
                ["pluginId"], references: JsPluginModel.databaseTableName, onDelete: .cascade)
        }
    }
}

extension JsRuntimeKvPairModel: TableRecord {
    static let databaseTableName = "jsruntimekvpair"
}

extension JsRuntimeKvPairModel: Codable, FetchableRecord, PersistableRecord {}
