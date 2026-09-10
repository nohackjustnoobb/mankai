//
//  MangaSnapshotService.swift
//  mankai
//
//  Created by Travis XU on 10/9/2026.
//

import Combine
import Foundation
import GRDB

/// Manages the locally persisted snapshot of manga metadata.
final class MangaSnapshotService: ObservableObject, @unchecked Sendable {
    struct Upsert {
        let manga: Manga
        let pluginId: String
    }

    enum Change {
        case upserted([Upsert])
        case deleted(mangaId: String, pluginId: String)
    }

    static let shared = MangaSnapshotService()

    private let changeSubject = PassthroughSubject<Change, Never>()

    /// Publishes snapshot changes after their database transaction commits.
    var changes: AnyPublisher<Change, Never> { changeSubject.eraseToAnyPublisher() }

    private init() { Logger.mangaSnapshotService.debug("Initializing MangaSnapshotService") }

    /// Returns a decoded manga snapshot, or `nil` when it is unavailable or invalid.
    func get(mangaId: String, pluginId: String, in db: Database? = nil) -> Manga? {
        do {
            let snapshot: MangaModel?
            if let db {
                snapshot = try fetch(mangaId: mangaId, pluginId: pluginId, in: db)
            } else {
                snapshot = try DbService.shared.appDb?
                    .read { db in try self.fetch(mangaId: mangaId, pluginId: pluginId, in: db) }
            }

            guard let snapshot else { return nil }

            return try decode(snapshot)
        } catch {
            Logger.mangaSnapshotService.error(
                "Failed to get manga snapshot \(mangaId) from plugin \(pluginId)", error: error)
            return nil
        }
    }

    /// Returns all valid decoded snapshots for the requested manga IDs.
    func get(mangaIds: [String], pluginId: String, in db: Database? = nil) -> [String: Manga] {
        guard !mangaIds.isEmpty else { return [:] }

        do {
            let snapshots: [MangaModel]
            if let db {
                snapshots = try fetch(mangaIds: mangaIds, pluginId: pluginId, in: db)
            } else {
                snapshots =
                    try DbService.shared.appDb?
                    .read { db in try self.fetch(mangaIds: mangaIds, pluginId: pluginId, in: db) }
                    ?? []
            }

            var mangas: [String: Manga] = [:]
            for snapshot in snapshots {
                do { mangas[snapshot.mangaId] = try decode(snapshot) } catch {
                    Logger.mangaSnapshotService.error(
                        "Failed to decode manga snapshot \(snapshot.mangaId) from plugin \(pluginId)",
                        error: error)
                }
            }
            return mangas
        } catch {
            Logger.mangaSnapshotService.error(
                "Failed to get manga snapshots from plugin \(pluginId)", error: error)
            return [:]
        }
    }

    /// Encodes manga metadata for local persistence.
    func makeSnapshot(for manga: Manga, pluginId: String) throws -> MangaModel {
        let data = try JSONEncoder().encode(manga)
        return MangaModel(
            mangaId: manga.id, pluginId: pluginId, info: String(decoding: data, as: UTF8.self))
    }

    /// Inserts or replaces a snapshot, optionally as part of the caller's database transaction.
    @discardableResult func upsert(
        _ snapshot: MangaModel, in db: Database? = nil, publishesChange: Bool = true
    ) throws -> Upsert? {
        if let db {
            try snapshot.upsert(db)
            let upsert = try? makeUpsert(from: snapshot)
            if publishesChange, let upsert { publish(.upserted([upsert]), afterCommitIn: db) }
            return upsert
        } else {
            guard let appDb = DbService.shared.appDb else {
                throw MankaiErrorCode.libraryFailedToUpdateSavedManga.makeError()
            }
            return try appDb.write { db in
                try self.upsert(snapshot, in: db, publishesChange: publishesChange)
            }
        }
    }

    /// Inserts or replaces multiple snapshots and optionally emits one change for the batch.
    @discardableResult func batchUpsert(
        _ snapshots: [MangaModel], in db: Database, publishesChange: Bool = true
    ) throws -> [Upsert] {
        var upserts: [Upsert] = []
        upserts.reserveCapacity(snapshots.count)

        for snapshot in snapshots {
            try snapshot.upsert(db)
            if let upsert = try? makeUpsert(from: snapshot) { upserts.append(upsert) }
        }

        if publishesChange, !upserts.isEmpty { publish(.upserted(upserts), afterCommitIn: db) }

        return upserts
    }

    /// Updates an existing snapshot, optionally as part of the caller's database transaction.
    @discardableResult func update(
        _ snapshot: MangaModel, in db: Database? = nil, publishesChange: Bool = true
    ) throws -> Upsert? {
        if let db {
            try snapshot.update(db)
            let upsert = try? makeUpsert(from: snapshot)
            if publishesChange, let upsert { publish(.upserted([upsert]), afterCommitIn: db) }
            return upsert
        } else {
            guard let appDb = DbService.shared.appDb else {
                throw MankaiErrorCode.libraryFailedToUpdateSavedManga.makeError()
            }
            return try appDb.write { db in
                try self.update(snapshot, in: db, publishesChange: publishesChange)
            }
        }
    }

    /// Deletes a snapshot, optionally as part of the caller's database transaction.
    @discardableResult func delete(
        mangaId: String, pluginId: String, in db: Database? = nil, publishesChange: Bool = true
    ) throws -> Bool {
        if let db {
            return try delete(
                mangaId: mangaId, pluginId: pluginId, from: db, publishesChange: publishesChange)
        }

        guard let appDb = DbService.shared.appDb else {
            throw MankaiErrorCode.libraryFailedToDeleteSavedManga.makeError()
        }
        return try appDb.write { db in
            try self.delete(
                mangaId: mangaId, pluginId: pluginId, from: db, publishesChange: publishesChange)
        }
    }

    private func fetch(mangaId: String, pluginId: String, in db: Database) throws -> MangaModel? {
        try MangaModel.filter(Column("mangaId") == mangaId && Column("pluginId") == pluginId)
            .fetchOne(db)
    }

    private func fetch(mangaIds: [String], pluginId: String, in db: Database) throws -> [MangaModel]
    {
        try MangaModel.filter(
            mangaIds.contains(Column("mangaId")) && Column("pluginId") == pluginId
        )
        .fetchAll(db)
    }

    private func delete(mangaId: String, pluginId: String, from db: Database, publishesChange: Bool)
        throws -> Bool
    {
        let deleted =
            try MangaModel.filter(Column("mangaId") == mangaId && Column("pluginId") == pluginId)
            .deleteAll(db) > 0

        if deleted, publishesChange {
            publish(.deleted(mangaId: mangaId, pluginId: pluginId), afterCommitIn: db)
        }

        return deleted
    }

    private func publish(_ change: Change, afterCommitIn db: Database) {
        db.afterNextTransaction { _ in DispatchQueue.main.async { self.changeSubject.send(change) }
        }
    }

    private func decode(_ snapshot: MangaModel) throws -> Manga {
        try JSONDecoder().decode(Manga.self, from: Data(snapshot.info.utf8))
    }

    private func makeUpsert(from snapshot: MangaModel) throws -> Upsert {
        Upsert(manga: try decode(snapshot), pluginId: snapshot.pluginId)
    }
}
