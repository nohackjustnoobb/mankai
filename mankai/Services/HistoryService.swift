//
//  HistoryService.swift
//  mankai
//
//  Created by Travis XU on 17/7/2025.
//

import Foundation
import GRDB

class HistoryService: ObservableObject {
    /// The shared singleton instance of HistoryService.
    static let shared = HistoryService()

    private init() {
        Logger.historyService.debug("Initializing HistoryService")
    }

    /// Retrieves a history record for a specific manga.
    /// - Parameters:
    ///   - mangaId: The ID of the manga.
    ///   - pluginId: The ID of the plugin providing the manga.
    /// - Returns: The `RecordModel` if found, otherwise `nil`.
    func get(mangaId: String, pluginId: String) -> RecordModel? {
        Logger.historyService.debug("Getting history for mangaId: \(mangaId), pluginId: \(pluginId)")
        do {
            return try DbService.shared.appDb?.read { db in
                try RecordModel
                    .filter(Column("mangaId") == mangaId && Column("pluginId") == pluginId)
                    .fetchOne(db)
            }
        } catch {
            Logger.historyService.error("Failed to get history record", error: error)
            return nil
        }
    }

    /// Retrieves multiple history records based on a list of IDs.
    /// - Parameter ids: A list of tuples containing mangaId and pluginId.
    /// - Returns: A list of `RecordModel` objects found.
    func get(ids: [(mangaId: String, pluginId: String)]) -> [RecordModel] {
        Logger.historyService.debug("Getting history for \(ids.count) records")
        do {
            let keys = ids.map { ["mangaId": $0.mangaId, "pluginId": $0.pluginId] }
            let result = try DbService.shared.appDb?.read { db in
                try RecordModel.fetchAll(db, keys: keys)
            }
            return result ?? []
        } catch {
            Logger.historyService.error("Failed to get history records", error: error)
            return []
        }
    }

    /// Adds or updates a history record and updates the corresponding saved record if it exists.
    /// - Parameters:
    ///   - record: The `RecordModel` to add.
    ///   - manga: The optional `MangaModel` associated with the record.
    /// - Returns: `true` if successful, throws an error if an error occurred.
    func add(record: RecordModel, manga: MangaModel? = nil) async throws -> Bool {
        Logger.historyService.debug("Adding history record for mangaId: \(record.mangaId)")
        let result = try await update(record: record, manga: manga)

        do {
            try await DbService.shared.appDb?.write { db in
                // Set updates to false in the corresponding saved if it exists
                if var saved =
                    try SavedModel
                        .filter(
                            Column("mangaId") == record.mangaId && Column("pluginId") == record.pluginId
                                && Column("updates") == true
                        )
                        .fetchOne(db)
                {
                    saved.updates = false
                    saved.datetime = Date()
                    try saved.update(db)
                }
            }
        } catch {
            Logger.historyService.error("Failed to update saved model after adding history", error: error)
            throw error
        }

        return result
    }

    /// Updates or inserts a history record.
    /// - Parameters:
    ///   - record: The `RecordModel` to update.
    ///   - manga: The optional `MangaModel` to update.
    /// - Returns: `true` if successful, throws an error if an error occurred.
    func update(record: RecordModel, manga: MangaModel? = nil) async throws -> Bool {
        Logger.historyService.debug("Updating history record for mangaId: \(record.mangaId)")
        var result: Bool?
        do {
            result = try await DbService.shared.appDb?.write { db in
                if let manga = manga {
                    try? manga.update(db)
                }
                try record.upsert(db)

                return true
            }
        } catch {
            Logger.historyService.error("Failed to update history record", error: error)
            throw error
        }

        guard let result = result else {
            Logger.historyService.error("Failed to update history record")
            throw MankaiErrorCode.historyFailedToUpdateHistoryRecord.makeError()
        }

        await MainActor.run {
            self.objectWillChange.send()
        }

        return result
    }

    /// Batch updates multiple history records and manga models.
    /// - Parameters:
    ///   - records: The list of `RecordModel` objects to update.
    ///   - mangas: The optional list of `MangaModel` objects to update.
    /// - Returns: `true` if successful, throws an error if an error occurred.
    func batchUpdate(records: [RecordModel], mangas: [MangaModel]? = nil) async throws -> Bool {
        Logger.historyService.debug("Batch updating \(records.count) records")
        var result: Bool?
        do {
            result = try await DbService.shared.appDb?.write { db in
                if let mangas = mangas {
                    for manga in mangas {
                        try? manga.update(db)
                    }
                }

                for record in records {
                    try record.upsert(db)
                }

                return true
            }
        } catch {
            Logger.historyService.error("Failed to batch update history records", error: error)
            throw error
        }

        guard let result = result else {
            Logger.historyService.error("Failed to batch update history records")
            throw MankaiErrorCode.historyFailedToUpdateHistoryRecord.makeError()
        }

        await MainActor.run {
            self.objectWillChange.send()
        }

        return result
    }

    /// Retrieves all history records with optional pagination.
    /// - Parameters:
    ///   - limit: The maximum number of records to retrieve.
    ///   - offset: The offset to start retrieving records from.
    /// - Returns: A list of `RecordModel` objects.
    func getAll(limit: Int? = nil, offset: Int = 0, shouldSync: Bool? = nil) -> [RecordModel] {
        Logger.historyService.debug(
            "Getting all history records, limit: \(String(describing: limit)), offset: \(offset)"
        )
        do {
            let result = try DbService.shared.appDb?.read { db in
                var request = RecordModel.order(Column("datetime").desc)

                if let limit = limit {
                    request = request.limit(limit, offset: offset)
                }

                if let shouldSync = shouldSync {
                    request = request.filter(Column("shouldSync") == shouldSync)
                }

                return try request.fetchAll(db)
            }
            return result ?? []
        } catch {
            Logger.historyService.error("Failed to get all history records", error: error)
            return []
        }
    }

    /// Retrieves all history records updated since a specific date.
    /// - Parameter date: The date to filter records by.
    /// - Returns: A list of `RecordModel` objects.
    func getAllSince(date: Date?, shouldSync: Bool? = nil) -> [RecordModel] {
        Logger.historyService.debug("Getting history records since: \(String(describing: date))")
        do {
            let result = try DbService.shared.appDb?.read { db in
                var request = RecordModel.order(Column("datetime").desc)

                if let shouldSync = shouldSync {
                    request = request.filter(Column("shouldSync") == shouldSync)
                }

                if let date = date {
                    request = request.filter(Column("datetime") > date)
                }

                return try request.fetchAll(db)
            }
            return result ?? []
        } catch {
            Logger.historyService.error("Failed to get history records since date", error: error)
            return []
        }
    }

    //    func delete(mangaId: String, pluginId: String) -> Bool? {
    //        let result = try? DbService.shared.appDb?.write { db in
    //            let deleted =
    //                try RecordModel
    //                    .filter(Column("mangaId") == mangaId && Column("pluginId") == pluginId)
    //                    .deleteAll(db)
    //
    //            let savedExists =
    //                try SavedModel
    //                    .filter(Column("mangaId") == mangaId && Column("pluginId") == pluginId)
    //                    .fetchCount(db) > 0
    //
    //            if !savedExists {
    //                try MangaModel
    //                    .filter(Column("mangaId") == mangaId && Column("pluginId") == pluginId)
    //                    .deleteAll(db)
    //            }
    //
    //            return deleted > 0
    //        }
    //
    //        objectWillChange.send()
    //        return result
    //    }
}
