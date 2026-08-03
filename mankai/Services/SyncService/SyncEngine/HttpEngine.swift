//
//  HttpEngine.swift
//  mankai
//
//  Created by Travis XU on 4/8/2025.
//

import Foundation

final class HttpEngine: SyncEngine {
    static let shared = HttpEngine()

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

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
                var body: [String: Any] = [:]

                body["saveds"] = newLocalSaveds.map { saved in
                    [
                        "mangaId": saved.mangaId,
                        "pluginId": saved.pluginId,
                        "datetime": Int(saved.datetime.timeIntervalSince1970 * 1000),
                        "updates": saved.updates,
                        "latestChapter": saved.latestChapter,
                    ]
                }

                body["records"] = newLocalRecords.map { record in
                    var dict: [String: Any] = [
                        "mangaId": record.mangaId,
                        "pluginId": record.pluginId,
                        "datetime": Int(record.datetime.timeIntervalSince1970 * 1000),
                        "page": record.page,
                        "chapterId": record.chapterId,
                    ]
                    if let chapterTitle = record.chapterTitle { dict["chapterTitle"] = chapterTitle }
                    return dict
                }

                let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
                (data, _) = try await authManager.post(path: "/sync", query: query, body: bodyData)
                isFirstRequest = false
            } else {
                (data, _) = try await authManager.get(path: "/sync", query: query)
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Logger.httpEngine.error("Invalid sync response format")
                break
            }

            // Handle Saveds
            if let savedsArr = json["saveds"] as? [[String: Any]] {
                let receivedSaveds = savedsArr.compactMap { dict -> SavedModel? in
                    guard let mangaId = dict["mangaId"] as? String,
                          let pluginId = dict["pluginId"] as? String,
                          let datetimeStr = dict["datetime"] as? String,
                          let updates = dict["updates"] as? Bool,
                          let latestChapter = dict["latestChapter"] as? String,
                          let datetime = HttpEngine.iso8601Formatter.date(from: datetimeStr)
                    else { return nil }
                    return SavedModel(
                        mangaId: mangaId, pluginId: pluginId, datetime: datetime, updates: updates,
                        latestChapter: latestChapter
                    )
                }

                if !receivedSaveds.isEmpty {
                    _ = try await SavedService.shared.batchUpdate(saveds: receivedSaveds)
                }
            }

            // Handle Records
            if let recordsArr = json["records"] as? [[String: Any]] {
                let receivedRecords = recordsArr.compactMap { dict -> RecordModel? in
                    guard let mangaId = dict["mangaId"] as? String,
                          let pluginId = dict["pluginId"] as? String,
                          let datetimeStr = dict["datetime"] as? String,
                          let page = dict["page"] as? Int,
                          let chapterId = dict["chapterId"] as? String,
                          let datetime = HttpEngine.iso8601Formatter.date(from: datetimeStr)
                    else { return nil }
                    let chapterTitle = dict["chapterTitle"] as? String
                    return RecordModel(
                        mangaId: mangaId, pluginId: pluginId, datetime: datetime, chapterId: chapterId,
                        chapterTitle: chapterTitle, page: page
                    )
                }

                if !receivedRecords.isEmpty {
                    _ = try await HistoryService.shared.batchUpdate(records: receivedRecords)
                }
            }

            if let deletedArr = json["deleted"] as? [[String: Any]] {
                for dict in deletedArr {
                    if let mangaId = dict["mangaId"] as? String,
                       let pluginId = dict["pluginId"] as? String,
                       let datetimeStr = dict["datetime"] as? String,
                       let datetime = HttpEngine.iso8601Formatter.date(from: datetimeStr)
                    {
                        if let localSaved = SavedService.shared.get(mangaId: mangaId, pluginId: pluginId) {
                            if datetime > localSaved.datetime {
                                _ = try await SavedService.shared.delete(mangaId: mangaId, pluginId: pluginId)
                            }
                        }
                    }
                }
            }

            // Check pagination
            let savedsCount = (json["saveds"] as? [Any])?.count ?? 0
            let recordsCount = (json["records"] as? [Any])?.count ?? 0
            let deletedCount = (json["deleted"] as? [Any])?.count ?? 0

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
        let bodyArr: [[String: Any]] = saveds.map { saved in
            [
                "mangaId": saved.mangaId,
                "pluginId": saved.pluginId,
                "datetime": Int(saved.datetime.timeIntervalSince1970 * 1000),
                "updates": saved.updates,
                "latestChapter": saved.latestChapter,
            ]
        }
        let bodyData = try JSONSerialization.data(withJSONObject: bodyArr, options: [])
        _ = try await authManager.post(path: "/saveds/add", body: bodyData)
    }

    override func removeSaveds(_ saveds: [(mangaId: String, pluginId: String)]) async throws {
        Logger.httpEngine.debug("HttpEngine removing \(saveds.count) saveds")
        let bodyArr: [[String: Any]] = saveds.map { saved in
            [
                "mangaId": saved.mangaId,
                "pluginId": saved.pluginId,
            ]
        }
        let bodyData = try JSONSerialization.data(withJSONObject: bodyArr, options: [])
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
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hash = json["hash"] as? String
        else {
            Logger.httpEngine.error("HttpEngine invalid hash response")
            throw MankaiErrorCode.syncHttpInvalidHashResponse.makeError()
        }
        return hash
    }
}
