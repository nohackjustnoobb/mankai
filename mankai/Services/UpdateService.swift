//
//  UpdateService.swift
//  mankai
//
//  Created by Travis XU on 20/7/2025.
//

import Foundation

final class UpdateService: ObservableObject {
    /// The shared singleton instance of UpdateService.
    static let shared = UpdateService()

    private init() {
        Logger.updateService.debug("Initializing UpdateService")
    }

    /// The timestamp of the last update check.
    var lastUpdateTime: Date? {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "UpdateService.lastUpdateTime") as? Date
    }

    /// A flag indicating if an update process is currently in progress.
    @Published var isUpdating = false

    /// Triggers the update process to check for new manga chapters.
    /// - Throws: An error if the update process fails.
    func update() async throws {
        if isUpdating {
            Logger.updateService.debug("Update already in progress, skipping")
            return
        }

        await MainActor.run { isUpdating = true }
        defer {
            Task { @MainActor in isUpdating = false }
        }

        Logger.updateService.debug("Starting update process")

        do {
            try await internalUpdate()
        } catch {
            Logger.updateService.error("Update failed", error: error)
            if case .online = Reach().connectionStatus() {
                let message = String(localized: "failedToUpdateLibrary")
                NotificationService.shared.showError(String(format: message, error.localizedDescription))
            }
            throw error
        }
    }

    private func internalUpdate() async throws {
        // Check if sync is needed (only if sync engine is configured)
        if SyncService.shared.engine != nil {
            if let lastSyncTime = SyncService.shared.lastSyncTime {
                // Check if last sync was more than 1 minute ago
                let timeInterval = Date().timeIntervalSince(lastSyncTime)
                if timeInterval > 60 { // 1 minute in seconds
                    Logger.updateService.info("Syncing before update (last sync: \(lastSyncTime))")
                    do {
                        try await SyncService.shared.sync(wait: true, showError: false)
                    } catch {
                        Logger.updateService.error("Sync failed before update", error: error)
                        throw MankaiErrorCode.updateSyncFailed.makeError(underlyingError: error)
                    }
                }
            } else {
                // No sync has been performed yet
                Logger.updateService.info("Syncing before update (first sync)")
                do {
                    try await SyncService.shared.sync(wait: true, showError: false)
                } catch {
                    Logger.updateService.error("Initial sync failed", error: error)
                    throw MankaiErrorCode.updateSyncFailed.makeError(underlyingError: error)
                }
            }
        }

        // Get all saved mangas
        let saveds = SavedService.shared.getAll()
        Logger.updateService.debug("Found \(saveds.count) saved mangas to check for updates")

        // Group saveds by pluginId
        var savedsByPlugin: [String: [SavedModel]] = [:]
        for saved in saveds {
            if savedsByPlugin[saved.pluginId] == nil {
                savedsByPlugin[saved.pluginId] = []
            }
            savedsByPlugin[saved.pluginId]!.append(saved)
        }

        // Process each plugin's saved mangas
        var updatedSaveds: [SavedModel] = []
        var updatedMangaModels: [MangaModel] = []

        for (pluginId, pluginSaveds) in savedsByPlugin {
            Logger.updateService.debug(
                "Checking updates for plugin: \(pluginId) (\(pluginSaveds.count) mangas)"
            )
            // Get the plugin
            guard let plugin = PluginService.shared.getPlugin(pluginId) else {
                Logger.updateService.warning("Plugin not found: \(pluginId)")
                continue // Skip if plugin doesn't exist
            }

            // Get manga IDs for this plugin
            let mangaIds = pluginSaveds.map { $0.mangaId }

            // Fetch updated manga data from the plugin
            do {
                let updatedMangas = try await plugin.getMangas(mangaIds)
                Logger.updateService.debug(
                    "Fetched \(updatedMangas.count) updated mangas from plugin \(pluginId)"
                )

                // Create a dictionary for quick lookup
                var mangaDict: [String: Manga] = [:]
                for manga in updatedMangas {
                    mangaDict[manga.id] = manga
                }

                // Check for updates
                for saved in pluginSaveds {
                    guard let updatedManga = mangaDict[saved.mangaId] else {
                        continue // Skip if manga not found in updated data
                    }

                    // Check if there's a new chapter
                    var hasUpdate = false

                    if let newChapter = updatedManga.latestChapter {
                        let oldChapter = try Chapter.decode(saved.latestChapter)
                        hasUpdate = newChapter.id != oldChapter.id

                        if hasUpdate {
                            Logger.updateService.info(
                                "Found update for manga: \(saved.mangaId) (Plugin: \(pluginId))"
                            )
                            // Create updated saved model
                            var updatedSaved = saved
                            updatedSaved.latestChapter = newChapter.encode()
                            updatedSaved.datetime = Date()
                            updatedSaved.updates = true
                            updatedSaveds.append(updatedSaved)
                        }
                    }

                    // Update manga model in database
                    if let mangaInfoData = try? JSONEncoder().encode(updatedManga),
                       let mangaInfoString = String(data: mangaInfoData, encoding: .utf8)
                    {
                        let mangaModel = MangaModel(
                            mangaId: updatedManga.id,
                            pluginId: pluginId,
                            info: mangaInfoString
                        )
                        updatedMangaModels.append(mangaModel)
                    }
                }
            } catch {
                Logger.updateService.error("Error checking updates for plugin \(pluginId)", error: error)
                if case .online = Reach().connectionStatus() {
                    let message = String(localized: "failedToCheckUpdatesForPlugin")
                    NotificationService.shared.showWarning(String(format: message, pluginId))
                }

                // Skip this plugin if there's an error
                continue
            }
        }

        // Batch update all changed saveds and mangas
        _ = try await SavedService.shared.batchUpdate(saveds: updatedSaveds, mangas: updatedMangaModels)
        if !updatedSaveds.isEmpty {
            Logger.updateService.info("Batch updating \(updatedSaveds.count) saveds")
            do {
                try await SyncService.shared.sync()
            } catch {
                Logger.updateService.error("Sync failed after update", error: error)
            }
        } else {
            Logger.updateService.debug("No updates found")
        }

        // Update last update time
        UserDefaults.standard.set(Date(), forKey: "UpdateService.lastUpdateTime")

        await MainActor.run {
            self.objectWillChange.send()
        }
        Logger.updateService.debug("Update process completed")
    }
}
