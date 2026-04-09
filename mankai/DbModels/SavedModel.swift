//
//  SavedModel.swift
//  mankai
//
//  Created by Travis XU on 19/7/2025.
//

import Foundation
import GRDB

struct SavedModel {
    var mangaId: String
    var pluginId: String
    var datetime: Date
    var updates: Bool
    var latestChapter: String

    var shouldSync: Bool = true

    static func createTable(_ db: Database) throws {
        try db.create(table: SavedModel.databaseTableName, ifNotExists: true) {
            $0.primaryKey(["mangaId", "pluginId"])

            $0.column("mangaId", .text).notNull()
            $0.column("pluginId", .text).notNull()
            $0.column("datetime", .datetime).notNull()
            $0.column("updates", .boolean).notNull()
            $0.column("latestChapter", .text).notNull()

            $0.column("shouldSync", .boolean).notNull().defaults(to: true)
        }
    }
}

extension SavedModel: TableRecord {
    static let databaseTableName = "saved"
}

extension SavedModel: Codable, FetchableRecord, PersistableRecord {}

/// Encoding for latestChapter
extension Chapter {
    func encode() -> String {
        let id = self.id
        let title = self.title ?? ""
        let locked = self.locked ?? false
        return "\(id)|\(title)|\(locked)"
    }

    static func decode(_ encoded: String) throws -> Chapter {
        let parts = encoded.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)

        guard let id = parts.count > 0 && !parts[0].isEmpty ? String(parts[0]) : nil else {
            throw NSError(domain: "Chapter", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "missingChapterId")])
        }

        let title = parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : nil
        let locked = parts.count > 2 && !parts[2].isEmpty ? Bool(String(parts[2])) : nil

        return Chapter(id: id, title: title, locked: locked)
    }
}
