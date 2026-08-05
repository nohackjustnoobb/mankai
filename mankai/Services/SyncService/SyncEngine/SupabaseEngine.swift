//
//  SupabaseEngine.swift
//  mankai
//
//  Created by Travis XU on 1/2/2026.
//

import Foundation
import Supabase

/// Realtime is not used here because:
/// 1. Even with Realtime, fetching the state is still required to handle data changes that occurred while the app was closed.
/// 2. It is rare for users to use multiple devices to read at the exact same time.
/// 3. Realtime has a higher cost.
/// Therefore, it is not worth it to use Realtime for this use case.
final class SupabaseEngine: SyncEngine {
    static let shared = SupabaseEngine()

    private var supabase: SupabaseClient?
    private var _url: String?
    private var _key: String?

    override var id: String {
        return "SupabaseEngine"
    }

    override var name: String {
        return String(localized: "supabaseEngine")
    }

    override var active: Bool {
        return supabase != nil && supabase?.auth.currentUser != nil
    }

    var isConfigured: Bool {
        return supabase != nil
    }

    var currentUrl: String? {
        return _url
    }

    var currentKey: String? {
        return _key
    }

    var currentUser: User? {
        return supabase?.auth.currentUser
    }

    override init() {
        let defaults = UserDefaults.standard
        _url = defaults.string(forKey: "SupabaseEngine.url")
        _key = defaults.string(forKey: "SupabaseEngine.key")

        if let url = _url, let key = _key {
            if let validUrl = URL(string: url) {
                supabase = SupabaseClient(
                    supabaseURL: validUrl,
                    supabaseKey: key,
                    options: SupabaseClientOptions(
                        auth: .init(
                            autoRefreshToken: true,
                            emitLocalSessionAsInitialSession: true
                        )
                    )
                )
            }
        }
    }

    func configClient(url: String, key: String) throws {
        resetClient()

        guard let validUrl = URL(string: url) else {
            throw MankaiErrorCode.syncSupabaseInvalidUrl.makeError()
        }

        _url = url
        _key = key
        supabase = SupabaseClient(
            supabaseURL: validUrl,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(
                    autoRefreshToken: true,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )

        save()
    }

    func resetClient() {
        if supabase != nil {
            supabase = nil
            _url = nil
            _key = nil

            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: "SupabaseEngine.url")
            defaults.removeObject(forKey: "SupabaseEngine.key")

            Task { @MainActor in
                self.objectWillChange.send()
            }
        }
    }

    // MARK: - Authentication

    func login(provider: Provider) async throws {
        guard let supabase = supabase else {
            throw MankaiErrorCode.syncSupabaseNotConfigured.makeError()
        }

        Logger.supabaseEngine.info("Logging in with provider: \(provider)")
        try await supabase.auth.signInWithOAuth(
            provider: provider, redirectTo: URL(string: "mankai://login-callback")!
        )

        try? await SyncService.shared.onEngineChange()

        await MainActor.run {
            self.objectWillChange.send()
        }
    }

    func logout() async throws {
        guard let supabase = supabase else {
            throw MankaiErrorCode.syncSupabaseNotConfigured.makeError()
        }

        Logger.supabaseEngine.info("Logging out")
        try await supabase.auth.signOut()

        await MainActor.run {
            self.objectWillChange.send()
        }
    }

    func save() {
        let defaults = UserDefaults.standard

        defaults.set(_url, forKey: "SupabaseEngine.url")
        defaults.set(_key, forKey: "SupabaseEngine.key")
    }

    // MARK: - SyncEngine Overrides

    override func onSelected() async throws {
        Logger.supabaseEngine.debug("Selected")

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "SupabaseEngine.lastSyncTime.records")
        defaults.removeObject(forKey: "SupabaseEngine.lastSyncTime.saveds")
    }

    // MARK: - Sync Payloads

    private struct SyncPayload: Encodable {
        let saveds: [SyncSaved]
        let records: [SyncRecord]
    }

    private struct SyncSaved: Encodable {
        let mangaId: String
        let pluginId: String
        let datetime: String
        let updates: Bool
        let latestChapter: String

        init(from saved: SavedModel) {
            mangaId = saved.mangaId
            pluginId = saved.pluginId
            datetime = ISO8601DateFormatter().string(from: saved.datetime)
            updates = saved.updates
            latestChapter = saved.latestChapter
        }
    }

    private struct SyncRecord: Encodable {
        let mangaId: String
        let pluginId: String
        let datetime: String
        let chapterId: String?
        let chapterTitle: String?
        let page: Int

        init(from record: RecordModel) {
            mangaId = record.mangaId
            pluginId = record.pluginId
            datetime = ISO8601DateFormatter().string(from: record.datetime)
            chapterId = record.chapterId
            chapterTitle = record.chapterTitle
            page = record.page
        }
    }

    override func sync() async throws {
        guard let supabase = supabase else {
            throw MankaiErrorCode.syncSupabaseNotReady.makeError()
        }

        Logger.supabaseEngine.debug("Syncing")

        let defaults = UserDefaults.standard
        let now = Date()

        // Get last sync time
        let lastSavedsSync = defaults.object(forKey: "SupabaseEngine.lastSyncTime.saveds") as? Date
        let lastRecordsSync = defaults.object(forKey: "SupabaseEngine.lastSyncTime.records") as? Date

        // Get local data that needs to be synced
        let localSaveds = SavedService.shared.getAllSince(date: lastSavedsSync, shouldSync: true)
        let localRecords = HistoryService.shared.getAllSince(date: lastRecordsSync, shouldSync: true)

        // Upload local data via edge function
        let syncPayload = SyncPayload(
            saveds: localSaveds.map { SyncSaved(from: $0) },
            records: localRecords.map { SyncRecord(from: $0) }
        )

        Logger.supabaseEngine.debug(
            "Uploading \(localSaveds.count) saveds and \(localRecords.count) records"
        )
        try await supabase.functions.invoke("sync", options: .init(body: syncPayload))

        // Pull data from remote
        try await pullSaveds(defaults: defaults)
        try await pullRecords(defaults: defaults)

        // Update last sync time
        defaults.set(now, forKey: "SupabaseEngine.lastSyncTime.saveds")
        defaults.set(now, forKey: "SupabaseEngine.lastSyncTime.records")

        Logger.supabaseEngine.debug("Sync completed")
    }

    override func addSaveds(_ saveds: [SavedModel]) async throws {
        guard let supabase = supabase else {
            throw MankaiErrorCode.syncSupabaseNotReady.makeError()
        }

        guard !saveds.isEmpty else { return }

        Logger.supabaseEngine.debug("SupabaseEngine adding \(saveds.count) saveds via edge function")

        // Upload saveds via edge function (handles insert/update with conflict resolution)
        let syncPayload = SyncPayload(
            saveds: saveds.map { SyncSaved(from: $0) },
            records: []
        )

        try await supabase.functions.invoke("sync", options: .init(body: syncPayload))
        Logger.supabaseEngine.info("Uploaded \(saveds.count) saveds")
    }

    override func removeSaveds(_ saveds: [(mangaId: String, pluginId: String)]) async throws {
        guard let supabase = supabase, let userId = currentUser?.id else {
            throw MankaiErrorCode.syncSupabaseNotReady.makeError()
        }

        guard !saveds.isEmpty else { return }

        Logger.supabaseEngine.debug("SupabaseEngine removing \(saveds.count) saveds")

        let now = Date()

        // Mark each saved as deleted (soft delete)
        struct SoftDeleteUpdate: Encodable {
            let isDeleted: Bool
            let datetime: Date
        }

        let updatePayload = SoftDeleteUpdate(isDeleted: true, datetime: now)

        for saved in saveds {
            try await supabase.from("Saved")
                .update(updatePayload)
                .eq("userId", value: userId)
                .eq("mangaId", value: saved.mangaId)
                .eq("pluginId", value: saved.pluginId)
                .execute()
        }

        Logger.supabaseEngine.info("Marked \(saveds.count) saveds as deleted")
    }

    override func initialSync() async throws {
        Logger.supabaseEngine.info("Initial sync")

        let localSaveds = SavedService.shared.getAll(shouldSync: true)

        try await addSaveds(localSaveds)
    }

    // MARK: - Pull Logic

    private func pullSaveds(defaults _: UserDefaults) async throws {
        Logger.supabaseEngine.debug("Pulling saveds")

        // Fetch all remote saveds
        let allRemoteSaveds = try await getSaveds()

        // Separate deleted and non-deleted saveds
        let deletedSaveds = allRemoteSaveds.filter { $0.isDeleted }
        let activeSaveds = allRemoteSaveds.filter { !$0.isDeleted }

        // Delete local saveds that are marked as deleted in remote
        for saved in deletedSaveds {
            Logger.supabaseEngine.info("Deleting local saved marked as deleted: \(saved.mangaId)")
            _ = try await SavedService.shared.delete(mangaId: saved.mangaId, pluginId: saved.pluginId)
        }

        // Apply non-deleted saveds
        if !activeSaveds.isEmpty {
            let models = activeSaveds.map { s in
                SavedModel(
                    mangaId: s.mangaId,
                    pluginId: s.pluginId,
                    datetime: s.datetime,
                    updates: s.updates,
                    latestChapter: s.latestChapter
                )
            }
            Logger.supabaseEngine.info("Applying \(models.count) remote saveds")
            _ = try await SavedService.shared.batchUpdate(saveds: models)
        }
    }

    private func pullRecords(defaults: UserDefaults) async throws {
        Logger.supabaseEngine.debug("Pulling records")

        // Get last sync time for records
        let lastSyncTime = defaults.object(forKey: "SupabaseEngine.lastSyncTime.records") as? Date

        // Fetch remote records since last sync
        let remoteRecords = try await getRecords(lastSyncTime)
        if !remoteRecords.isEmpty {
            Logger.supabaseEngine.info("Applying \(remoteRecords.count) remote records")
            _ = try await HistoryService.shared.batchUpdate(records: remoteRecords)
        }
    }

    // MARK: - Internal Sync Logic

    private struct SupabaseSaved: Codable {
        let mangaId: String
        let pluginId: String
        let userId: UUID
        let datetime: Date
        let updates: Bool
        let latestChapter: String
        let isDeleted: Bool
        let updatedAt: Date?
    }

    private func getSaveds(_ since: Date? = nil) async throws -> [SupabaseSaved] {
        guard let supabase = supabase, let userId = currentUser?.id else {
            throw MankaiErrorCode.syncSupabaseNotReady.makeError()
        }

        Logger.supabaseEngine.debug("SupabaseEngine getting saveds since: \(String(describing: since))")

        var query = supabase.from("Saved")
            .select()
            .eq("userId", value: userId)

        if let since = since {
            let isoDate = ISO8601DateFormatter().string(from: since)
            query = query.gt("updatedAt", value: isoDate)
        }

        var allResults: [SupabaseSaved] = []
        var offset = 0
        let limit = 1000

        while true {
            let chunkQuery =
                query
                    .order("datetime", ascending: false)
                    .range(from: offset, to: offset + limit - 1)

            let chunk: [SupabaseSaved] = try await chunkQuery.execute().value

            allResults.append(contentsOf: chunk)

            if chunk.count < limit {
                break
            }
            offset += limit
        }

        return allResults
    }

    private struct SupabaseRecord: Codable {
        let mangaId: String
        let pluginId: String
        let userId: UUID
        let datetime: Date
        let chapterId: String
        let chapterTitle: String?
        let page: Int
        let updatedAt: Date?
    }

    private func getRecords(_ since: Date? = nil) async throws -> [RecordModel] {
        guard let supabase = supabase, let userId = currentUser?.id else {
            throw MankaiErrorCode.syncSupabaseNotReady.makeError()
        }

        Logger.supabaseEngine.debug(
            "SupabaseEngine getting records since: \(String(describing: since))"
        )

        // Supabase/PostgREST uses ISO8601 strings for date comparison
        var query = supabase.from("Record")
            .select() // Select all fields
            .eq("userId", value: userId)

        if let since = since {
            let isoDate = ISO8601DateFormatter().string(from: since)
            query = query.gt("updatedAt", value: isoDate)
        }

        // Pagination
        var allResults: [RecordModel] = []
        var offset = 0
        let limit = 1000 // max limit 1000

        while true {
            // Apply order and range to the filtered query
            let chunkQuery =
                query
                    .order("datetime", ascending: false)
                    .range(from: offset, to: offset + limit - 1)

            let chunk: [SupabaseRecord] = try await chunkQuery.execute().value

            let models = chunk.map { r in
                RecordModel(
                    mangaId: r.mangaId,
                    pluginId: r.pluginId,
                    datetime: r.datetime,
                    chapterId: r.chapterId,
                    chapterTitle: r.chapterTitle,
                    page: r.page
                )
            }

            allResults.append(contentsOf: models)

            if chunk.count < limit {
                break
            }
            offset += limit
        }

        return allResults
    }
}
