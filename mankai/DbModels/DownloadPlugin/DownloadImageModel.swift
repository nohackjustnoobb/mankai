//
//  DownloadImageModel.swift
//  mankai
//
//  Created by Travis XU on 19/7/2025.
//

import GRDB

struct DownloadImageModel {
    var id: Int?
    var url: String
    var mangaId: String  // pluginId+mangaId
    var path: String

    static func createTable(_ db: Database) throws {
        try db.create(table: DownloadImageModel.databaseTableName, ifNotExists: true) {
            $0.autoIncrementedPrimaryKey("id")
            $0.column("url", .text).notNull().unique().indexed()

            $0.column("mangaId", .text).notNull()
            $0.column("path", .text).notNull()

            $0.foreignKey(
                ["mangaId"], references: DownloadMangaModel.databaseTableName, onDelete: .cascade)
        }
    }
}

extension DownloadImageModel: TableRecord {
    static let databaseTableName = "downloadImage"

    static let manga = belongsTo(DownloadMangaModel.self)
}

extension DownloadImageModel: Codable, FetchableRecord, PersistableRecord {
    var manga: QueryInterfaceRequest<DownloadMangaModel> { request(for: DownloadImageModel.manga) }
}
