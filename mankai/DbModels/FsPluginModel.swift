//
//  FsPluginModel.swift
//  mankai
//
//  Created by Travis XU on 29/1/2026.
//

import Foundation
import GRDB

struct FsPluginModel {
    var id: String
    var isWriteable: Bool
    var bookmarkData: Data
    var shouldSync: Bool

    static func createTable(_ db: Database) throws {
        try db.create(table: FsPluginModel.databaseTableName, ifNotExists: true) {
            $0.primaryKey("id", .text)

            $0.column("isWriteable", .boolean).notNull()
            $0.column("bookmarkData", .blob).notNull()
            $0.column("shouldSync", .boolean).notNull()
        }
    }
}

extension FsPluginModel: TableRecord { static let databaseTableName = "fsplugin" }

extension FsPluginModel: Codable, FetchableRecord, PersistableRecord {}
