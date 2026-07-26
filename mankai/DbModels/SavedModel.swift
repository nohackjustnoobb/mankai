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
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "|", with: "\\|")
        }

        let id = escape(self.id)
        let title = escape(self.title ?? "")
        let locked = self.locked ?? false
        return "\(id)|\(title)|\(locked)"
    }

    static func decode(_ encoded: String) throws -> Chapter {
        // Split on unescaped `|`, keeping escaped pipes within a field.
        var parts: [String] = []
        var current = ""
        var iter = encoded.makeIterator()
        while let ch = iter.next() {
            if ch == "\\" {
                current.append(ch)
                if let next = iter.next() { current.append(next) }
            } else if ch == "|" {
                parts.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        parts.append(current)

        func unescape(_ s: String) -> String {
            var result = ""
            var it = s.makeIterator()
            while let ch = it.next() {
                if ch == "\\", let next = it.next() {
                    result.append(next)
                } else {
                    result.append(ch)
                }
            }
            return result
        }

        guard !parts.isEmpty, !parts[0].isEmpty else {
            throw MankaiErrorCode.chapterMissingChapterId.makeError()
        }

        let id = unescape(parts[0])
        let title = parts.count > 1 && !parts[1].isEmpty ? unescape(parts[1]) : nil
        let locked = parts.count > 2 && !parts[2].isEmpty ? Bool(parts[2]) : nil

        return Chapter(id: id, title: title, locked: locked)
    }
}
