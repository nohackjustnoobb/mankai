//
//  FsChapterModel.swift
//  mankai
//
//  Created by Travis XU on 19/7/2025.
//

import Foundation
import GRDB

struct FsChapterModel {
    var id: Int?
    var title: String
    var sequence: Int
    var chapterGroupId: Int

    static func createTable(_ db: Database) throws {
        try db.create(table: FsChapterModel.databaseTableName, ifNotExists: true) {
            $0.autoIncrementedPrimaryKey("id")

            $0.column("title", .text).notNull()
            $0.column("sequence", .integer).notNull()
            $0.column("chapterGroupId", .integer).notNull()

            $0.foreignKey(
                ["chapterGroupId"], references: FsChapterGroupModel.databaseTableName,
                onDelete: .cascade)
        }
    }
}

extension FsChapterModel: TableRecord {
    static let databaseTableName = "chapter"

    static let chapterGroup = belongsTo(FsChapterGroupModel.self)
}

extension FsChapterModel: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var chapterGroup: QueryInterfaceRequest<FsChapterGroupModel> {
        request(for: FsChapterModel.chapterGroup)
    }
}
