//
//  FsChapterGroupModel.swift
//  mankai
//
//  Created by Travis XU on 19/7/2025.
//

import GRDB

struct FsChapterGroupModel {
    var id: Int?
    var mangaId: String
    var title: String

    static func createTable(_ db: Database) throws {
        try db.create(table: FsChapterGroupModel.databaseTableName, ifNotExists: true) {
            $0.autoIncrementedPrimaryKey("id")

            $0.column("mangaId", .text).notNull()
            $0.column("title", .text).notNull()

            $0.foreignKey(
                ["mangaId"], references: FsMangaModel.databaseTableName, onDelete: .cascade)
        }
    }
}

extension FsChapterGroupModel: TableRecord {
    static let databaseTableName = "chapterGroup"

    static let manga = belongsTo(FsMangaModel.self)
    static let chapters = hasMany(FsChapterModel.self)
}

extension FsChapterGroupModel: Codable, FetchableRecord, PersistableRecord {
    var manga: QueryInterfaceRequest<FsMangaModel> { request(for: FsChapterGroupModel.manga) }

    var chapters: QueryInterfaceRequest<FsChapterModel> {
        request(for: FsChapterGroupModel.chapters)
    }
}
