//
//  RecordModel.swift
//  mankai
//
//  Created by Travis XU on 19/7/2025.
//

import Foundation
import GRDB

struct RecordModel {
    var mangaId: String
    var pluginId: String
    var datetime: Date
    var chapterId: String
    var chapterTitle: String?
    var page: Int

    var shouldSync: Bool = true

    static func createTable(_ db: Database) throws {
        try db.create(table: RecordModel.databaseTableName, ifNotExists: true) {
            $0.primaryKey(["mangaId", "pluginId"])

            $0.column("mangaId", .text).notNull()
            $0.column("pluginId", .text).notNull()
            $0.column("datetime", .datetime).notNull()
            $0.column("page", .integer).notNull()
            $0.column("chapterId", .text).notNull()
            $0.column("chapterTitle", .text)

            $0.column("shouldSync", .boolean).notNull().defaults(to: true)
        }
    }
}

extension RecordModel: TableRecord { static let databaseTableName = "record" }

extension RecordModel: Codable, FetchableRecord, PersistableRecord {}

extension RecordModel: Equatable {}
