//
//  SavedService.swift
//  mankai
//
//  Created by Travis XU on 17/7/2025.
//

import Combine
import CryptoKit
import Foundation
import GRDB

@MainActor final class SavedService: ObservableObject {
    enum Change {
        case upserted(saveds: [SavedModel], snapshots: [MangaSnapshotService.Upsert])
        case deleted(mangaId: String, pluginId: String)
    }

    /// The shared singleton instance of SavedService.
    static let shared = SavedService()

    private let changeSubject = PassthroughSubject<Change, Never>()

    /// Publishes the saved items affected by a successful database change.
    var changes: AnyPublisher<Change, Never> { changeSubject.eraseToAnyPublisher() }

    private init() { Logger.savedService.debug("Initializing SavedService") }

    /// Retrieves a saved manga record.
    /// - Parameters:
    ///   - mangaId: The ID of the manga.
    ///   - pluginId: The ID of the plugin providing the manga.
    /// - Returns: The `SavedModel` if found, otherwise `nil`.
    func get(mangaId: String, pluginId: String) -> SavedModel? {
        Logger.savedService.debug(
            "Getting saved manga for mangaId: \(mangaId), pluginId: \(pluginId)")
        do {
            return try DbService.shared.appDb?
                .read { db in
                    try SavedModel.filter(
                        Column("mangaId") == mangaId && Column("pluginId") == pluginId
                    )
                    .fetchOne(db)
                }
        } catch {
            Logger.savedService.error("Failed to get saved manga", error: error)
            return nil
        }
    }

    /// Adds a manga to the saved list and push to remote.
    /// - Parameters:
    ///   - saved: The `SavedModel` to add.
    ///   - manga: The optional `MangaModel` associated with the saved item.
    /// - Returns: `true` if successful, throws an error if an error occurred.
    func add(saved: SavedModel, manga: MangaModel? = nil) async throws -> Bool {
        Logger.savedService.debug("Adding saved manga: \(saved.mangaId)")
        let result = try await update(saved: saved, manga: manga)

        if result, saved.shouldSync, SyncService.shared.engine != nil {
            do { try await SyncService.shared.addSaved(saved) } catch {
                Logger.savedService.error("Failed to push saveds after adding", error: error)
                throw error
            }
        }

        return result
    }

    /// Removes a manga from the saved list and push to remote.
    /// - Parameters:
    ///   - mangaId: The ID of the manga to remove.
    ///   - pluginId: The ID of the plugin providing the manga.
    /// - Returns: `true` if successful, throws an error if an error occurred.
    func remove(mangaId: String, pluginId: String) async throws -> Bool {
        Logger.savedService.debug("Removing saved manga: \(mangaId)")
        let shouldSync = get(mangaId: mangaId, pluginId: pluginId)?.shouldSync == true
        let result = try await delete(mangaId: mangaId, pluginId: pluginId)

        if result, shouldSync, SyncService.shared.engine != nil {
            do {
                try await SyncService.shared.removeSaved(mangaId: mangaId, pluginId: pluginId)
            } catch {
                Logger.savedService.error("Failed to push saveds after removing", error: error)
                throw error
            }
        }

        return result
    }

    /// Updates an existing saved manga record.
    /// - Parameters:
    ///   - saved: The `SavedModel` to update.
    ///   - manga: The optional `MangaModel` to update.
    /// - Returns: `true` if successful, throws an error if an error occurred.
    func update(saved: SavedModel, manga: MangaModel? = nil) async throws -> Bool {
        Logger.savedService.debug("Updating saved manga: \(saved.mangaId)")
        let outcome: (result: Bool, snapshotUpserts: [MangaSnapshotService.Upsert])?
        do {
            var snapshotUpserts: [MangaSnapshotService.Upsert] = []
            if let manga, let upsert = try await MangaSnapshotService.shared.upsert(manga) {
                snapshotUpserts.append(upsert)
            }

            let result = try await DbService.shared.appDb?
                .write { db in
                    try saved.upsert(db)
                    return true
                }
            outcome = result.map { ($0, snapshotUpserts) }
        } catch {
            Logger.savedService.error("Failed to update saved manga", error: error)
            throw error
        }

        guard let outcome else {
            Logger.savedService.error("Failed to update saved manga")
            throw MankaiErrorCode.libraryFailedToUpdateSavedManga.makeError()
        }

        publish(.upserted(saveds: [saved], snapshots: outcome.snapshotUpserts))

        return outcome.result
    }

    /// Batch updates multiple saved manga records and manga models.
    /// - Parameters:
    ///   - saveds: The list of `SavedModel` objects to update.
    ///   - mangas: The optional list of `MangaModel` objects to update.
    /// - Returns: `true` if successful, throws an error if an error occurred.
    func batchUpdate(saveds: [SavedModel], mangas: [MangaModel]? = nil) async throws -> Bool {
        Logger.savedService.debug("Batch updating \(saveds.count) saved mangas")
        let outcome: (result: Bool, snapshotUpserts: [MangaSnapshotService.Upsert])?
        do {
            let snapshotUpserts: [MangaSnapshotService.Upsert]
            if let mangas {
                snapshotUpserts = try await MangaSnapshotService.shared.batchUpsert(mangas)
            } else {
                snapshotUpserts = []
            }

            let result = try await DbService.shared.appDb?
                .write { db in
                    for saved in saveds { try saved.upsert(db) }
                    return true
                }
            outcome = result.map { ($0, snapshotUpserts) }
        } catch {
            Logger.savedService.error("Failed to batch update saved mangas", error: error)
            throw error
        }

        guard let outcome else {
            Logger.savedService.error("Failed to batch update saved mangas")
            throw MankaiErrorCode.libraryFailedToUpdateSavedManga.makeError()
        }

        publish(.upserted(saveds: saveds, snapshots: outcome.snapshotUpserts))

        return outcome.result
    }

    /// Deletes a saved manga record and its associated manga model.
    /// - Parameters:
    ///   - mangaId: The ID of the manga to delete.
    ///   - pluginId: The ID of the plugin providing the manga.
    /// - Returns: `true` if successful, throws an error if an error occurred.
    func delete(mangaId: String, pluginId: String) async throws -> Bool {
        Logger.savedService.debug("Deleting saved manga: \(mangaId)")
        var result: Bool?
        do {
            result = try await DbService.shared.appDb?
                .write { db in
                    try SavedModel
                        .filter(Column("mangaId") == mangaId && Column("pluginId") == pluginId)
                        .deleteAll(db) > 0
                }

            _ = try await MangaSnapshotService.shared.delete(mangaId: mangaId, pluginId: pluginId)
        } catch {
            Logger.savedService.error("Failed to delete saved manga", error: error)
            throw error
        }

        guard let result = result else {
            Logger.savedService.error("Failed to delete saved manga")
            throw MankaiErrorCode.libraryFailedToDeleteSavedManga.makeError()
        }

        publish(.deleted(mangaId: mangaId, pluginId: pluginId))

        return result
    }

    /// Retrieves all saved manga records.
    /// - Returns: A list of `SavedModel` objects.
    func getAll(shouldSync: Bool? = nil) -> [SavedModel] {
        Logger.savedService.debug("Getting all saved mangas")
        do {
            let result = try DbService.shared.appDb?
                .read { db in
                    var request = SavedModel.order(Column("datetime").desc)

                    if let shouldSync = shouldSync {
                        request = request.filter(Column("shouldSync") == shouldSync)
                    }

                    return try request.fetchAll(db)
                }
            return result ?? []
        } catch {
            Logger.savedService.error("Failed to get all saved mangas", error: error)
            return []
        }
    }

    /// Retrieves all saved manga records updated since a specific date.
    /// - Parameter date: The date to filter records by.
    /// - Returns: A list of `SavedModel` objects.
    func getAllSince(date: Date?, shouldSync: Bool? = nil) -> [SavedModel] {
        Logger.savedService.debug("Getting saved mangas since: \(String(describing: date))")
        do {
            let result = try DbService.shared.appDb?
                .read { db in
                    var request = SavedModel.order(Column("datetime").asc)

                    if let shouldSync = shouldSync {
                        request = request.filter(Column("shouldSync") == shouldSync)
                    }

                    if let date = date { request = request.filter(Column("datetime") > date) }

                    return try request.fetchAll(db)
                }
            return result ?? []
        } catch {
            Logger.savedService.error("Failed to get saved mangas since date", error: error)
            return []
        }
    }

    /// Generates a hash string representing the current state of saved mangas.
    /// - Returns: A SHA256 hash string, or `nil` if generation fails.
    func generateHash() async -> String? {
        Logger.savedService.debug("Generating hash for saved mangas")
        guard let appDb = DbService.shared.appDb else { return nil }

        do {
            return try await appDb.read { db in
                // Fetch all saved items, sorted by mangaId and pluginId
                let saveds = try SavedModel.filter(Column("shouldSync") == true)
                    .order(Column("mangaId").asc, Column("pluginId").asc).fetchAll(db)

                // Concatenate primary keys
                let keyString = saveds.map { "\($0.mangaId)|\($0.pluginId)" }.joined()

                // Generate SHA256 hash on the database executor.
                let data = Data(keyString.utf8)
                let hash = SHA256.hash(data: data)

                return hash.compactMap { String(format: "%02x", $0) }.joined()
            }
        } catch {
            Logger.savedService.error("Failed to generate hash for saved mangas", error: error)
            return nil
        }
    }

    private func publish(_ change: Change) {
        changeSubject.send(change)
        objectWillChange.send()
    }
}
