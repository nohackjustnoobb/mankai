//
//  FsImageModel.swift
//  mankai
//
//  Created by Travis XU on 19/7/2025.
//

import GRDB

struct FsImageModel {
    var id: String
    var path: String
    var width: Int
    var height: Int
    var mangaId: String?
    var chapterId: Int?
    var sequence: Int?

    static func createTable(_ db: Database) throws {
        try db.create(table: FsImageModel.databaseTableName, ifNotExists: true) {
            $0.primaryKey("id", .text)

            $0.column("path", .text).notNull()
            $0.column("width", .integer).notNull()
            $0.column("height", .integer).notNull()

            $0.column("mangaId", .text)
            $0.column("chapterId", .integer)
            $0.column("sequence", .integer)

            $0.foreignKey(
                ["mangaId"], references: FsMangaModel.databaseTableName, onDelete: .cascade)
            $0.foreignKey(
                ["chapterId"], references: FsChapterModel.databaseTableName, onDelete: .cascade)
        }
    }
}

extension FsImageModel: TableRecord {
    static let databaseTableName = "image"

    static let manga = belongsTo(FsMangaModel.self)
    static let chapter = belongsTo(FsChapterModel.self)
}

extension FsImageModel: Codable, FetchableRecord, PersistableRecord {
    var manga: QueryInterfaceRequest<FsMangaModel> { request(for: FsImageModel.manga) }

    var chapter: QueryInterfaceRequest<FsChapterModel> { request(for: FsImageModel.chapter) }
}
