//
//  HttpEngine.swift
//  mankai
//
//  Created by Travis XU on 4/8/2025.
//

import Foundation
import ReerCodable

final class HttpEngine: SyncEngine {
    static let shared = HttpEngine()

    // MARK: - HTTP Models

    private struct SyncRequest: Encodable {
        let saveds: [SyncSaved]
        let records: [SyncRecord]
    }

    @Codable
    fileprivate struct SyncSaved {
        let mangaId: String
        let pluginId: String
        @CustomCoding(FlexibleDateCoding.self)
        let datetime: Date
        let updates: Bool
        let latestChapter: String

        init(from saved: SavedModel) {
            mangaId = saved.mangaId
            pluginId = saved.pluginId
            datetime = saved.datetime
            updates = saved.updates
            latestChapter = saved.latestChapter
        }

        func toModel() -> SavedModel {
            SavedModel(
                mangaId: mangaId,
                pluginId: pluginId,
                datetime: datetime,
                updates: updates,
                latestChapter: latestChapter
            )
        }
    }

    @Codable
    fileprivate struct SyncRecord {
        let mangaId: String
        let pluginId: String
        @CustomCoding(FlexibleDateCoding.self)
        let datetime: Date
        let page: Int
        let chapterId: String
        let chapterTitle: String?

        init(from record: RecordModel) {
            mangaId = record.mangaId
            pluginId = record.pluginId
            datetime = record.datetime
            page = record.page
            chapterId = record.chapterId
            chapterTitle = record.chapterTitle
        }

        func toModel() -> RecordModel {
            RecordModel(
                mangaId: mangaId,
                pluginId: pluginId,
                datetime: datetime,
                chapterId: chapterId,
                chapterTitle: chapterTitle,
                page: page
            )
        }
    }

    @Decodable
    fileprivate struct DeletedItem {
        let mangaId: String
        let pluginId: String
        @CustomCoding(FlexibleDateCoding.self)
        let datetime: Date
    }

    @Decodable
    fileprivate struct SyncResponse {
        @DecodingDefault([])
        let saveds: [SyncSaved]
        @DecodingDefault([])
        let records: [SyncRecord]
        @DecodingDefault([])
        let deleted: [DeletedItem]
    }

    private struct SavedReference: Encodable {
        let mangaId: String
        let pluginId: String
    }

    private struct HashResponse: Decodable {
        let hash: String
    }

    private let authManager: AuthManager

    override private init() {
        authManager = AuthManager(id: "HttpEngine")

        super.init()
        authManager.postSave = { [weak self] in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }

        authManager.postLogin = { [weak self] in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }

            Task {
                try? await SyncService.shared.onEngineChange()
            }
        }

        Logger.httpEngine.debug("HttpEngine initialized")
    }

    override var id: String {
        return "HttpEngine"
    }

    override var name: String {
        return String(localized: "httpEngine")
    }

    var username: String? {
        return authManager.username
    }

    var serverUrl: String? {
        get {
            return authManager.serverUrl
        }
        set {
            authManager.serverUrl = newValue

            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }

    override var active: Bool {
        return authManager.loggedIn
    }

    // MARK: - Authentication

    func login(username: String, password: String) async throws {
        Logger.httpEngine.info("Logging in with username: \(username)")
        try await authManager.login(username: username, password: password)
        Logger.httpEngine.info("Login successful")
    }

    func logout() {
        Logger.httpEngine.info("Logging out")
        authManager.logout()
    }

    // MARK: - SyncEngine Overrides

    override func onSelected() async throws {
        Logger.httpEngine.debug("Selected")

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "HttpEngine.lastSyncTime")
    }

    override func sync() async throws {
        Logger.httpEngine.debug("Syncing")

        let defaults = UserDefaults.standard

        // Get last sync time
        let lastSyncTime = defaults.object(forKey: "HttpEngine.lastSyncTime") as? Date
        let now = Date()

        // Fetch new local saveds since last sync
        let newLocalSaveds = SavedService.shared.getAllSince(date: lastSyncTime, shouldSync: true)

        // Fetch new local records since last sync
        let newLocalRecords = HistoryService.shared.getAllSince(date: lastSyncTime, shouldSync: true)

        var offset = 0
        let limit = 50

        var hasMorePages = true
        var isFirstRequest = true

        while hasMorePages {
            var query: [String: String] = [
                "os": String(offset),
                "lm": String(limit),
            ]
            if let since = lastSyncTime {
                let ts = Int(since.timeIntervalSince1970 * 1000)
                query["ts"] = String(ts)
            }

            let data: Data

            if isFirstRequest {
                let body = SyncRequest(
                    saveds: newLocalSaveds.map { SyncSaved(from: $0) },
                    records: newLocalRecords.map { SyncRecord(from: $0) }
                )
                let bodyData = try JSONEncoder().encode(body)
                (data, _) = try await authManager.post(path: "/sync", query: query, body: bodyData)
                isFirstRequest = false
            } else {
                (data, _) = try await authManager.get(path: "/sync", query: query)
            }

            guard let response = try? JSONDecoder().decode(SyncResponse.self, from: data) else {
                Logger.httpEngine.error("Invalid sync response format")
                break
            }

            // Handle Saveds
            if !response.saveds.isEmpty {
                _ = try await SavedService.shared.batchUpdate(
                    saveds: response.saveds.map { $0.toModel() }
                )
            }

            // Handle Records
            if !response.records.isEmpty {
                _ = try await HistoryService.shared.batchUpdate(
                    records: response.records.map { $0.toModel() }
                )
            }

            for deleted in response.deleted {
                if let localSaved = SavedService.shared.get(
                    mangaId: deleted.mangaId,
                    pluginId: deleted.pluginId
                ) {
                    if deleted.datetime > localSaved.datetime {
                        _ = try await SavedService.shared.delete(
                            mangaId: deleted.mangaId,
                            pluginId: deleted.pluginId
                        )
                    }
                }
            }

            // Check pagination
            let savedsCount = response.saveds.count
            let recordsCount = response.records.count
            let deletedCount = response.deleted.count

            if savedsCount >= limit || recordsCount >= limit || deletedCount >= limit {
                offset += limit
            } else {
                hasMorePages = false
            }
        }

        // Update last sync time
        defaults.set(now, forKey: "HttpEngine.lastSyncTime")

        Logger.httpEngine.debug("Sync completed")
    }

    override func addSaveds(_ saveds: [SavedModel]) async throws {
        Logger.httpEngine.debug("HttpEngine adding \(saveds.count) saveds")
        let body = saveds.map { SyncSaved(from: $0) }
        let bodyData = try JSONEncoder().encode(body)
        _ = try await authManager.post(path: "/saveds/add", body: bodyData)
    }

    override func removeSaveds(_ saveds: [(mangaId: String, pluginId: String)]) async throws {
        Logger.httpEngine.debug("HttpEngine removing \(saveds.count) saveds")
        let body = saveds.map {
            SavedReference(mangaId: $0.mangaId, pluginId: $0.pluginId)
        }
        let bodyData = try JSONEncoder().encode(body)
        _ = try await authManager.post(path: "/saveds/remove", body: bodyData)
    }

    override func initialSync() async throws {
        Logger.httpEngine.info("Initial sync")

        // Get hash from remote server
        let remoteHash = try await getSavedsHash()

        // Get local hash
        let localHash = SavedService.shared.generateHash()

        // Compare hashes
        if remoteHash != localHash {
            Logger.httpEngine.info("Hashes mismatch, syncing saveds")

            // Fetch local saveds
            let localSaveds = SavedService.shared.getAll(shouldSync: true)

            // Push all local saveds to remote
            try await addSaveds(localSaveds)
        } else {
            Logger.httpEngine.debug("Hashes match, skipping saveds sync")
        }
    }

    // MARK: - Helpers

    private func getSavedsHash() async throws -> String {
        Logger.httpEngine.debug("HttpEngine getting saveds hash")
        let (data, _) = try await authManager.get(path: "/saveds/hash")
        guard let response = try? JSONDecoder().decode(HashResponse.self, from: data) else {
            Logger.httpEngine.error("HttpEngine invalid hash response")
            throw MankaiErrorCode.syncHttpInvalidHashResponse.makeError()
        }
        return response.hash
    }
}
