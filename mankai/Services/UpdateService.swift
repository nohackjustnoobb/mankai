//
//  UpdateService.swift
//  mankai
//
//  Created by Travis XU on 20/7/2025.
//

import Foundation
import GRDB

final class UpdateService: ObservableObject {
    /// The shared singleton instance of UpdateService.
    static let shared = UpdateService()

    private init() { Logger.updateService.debug("Initializing UpdateService") }

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
        defer { Task { @MainActor in isUpdating = false } }

        Logger.updateService.debug("Starting update process")

        do { try await internalUpdate() } catch {
            Logger.updateService.error("Update failed", error: error)
            if case .online = Reach().connectionStatus() {
                let message = String(localized: "failedToUpdateLibraryFormat")
                NotificationService.shared.showError(
                    String(format: message, error.localizedDescription))
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
                if timeInterval > 60 {  // 1 minute in seconds
                    Logger.updateService.info("Syncing before update (last sync: \(lastSyncTime))")
                    do { try await SyncService.shared.sync(wait: true, showError: false) } catch {
                        Logger.updateService.error("Sync failed before update", error: error)
                        throw MankaiErrorCode.updateSyncFailed.makeError(underlyingError: error)
                    }
                }
            } else {
                // No sync has been performed yet
                Logger.updateService.info("Syncing before update (first sync)")
                do { try await SyncService.shared.sync(wait: true, showError: false) } catch {
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
            if savedsByPlugin[saved.pluginId] == nil { savedsByPlugin[saved.pluginId] = [] }
            savedsByPlugin[saved.pluginId]!.append(saved)
        }

        // Process each plugin's saved mangas
        var updatedSaveds: [SavedModel] = []
        var updatedMangaModels: [MangaModel] = []

        for (pluginId, pluginSaveds) in savedsByPlugin {
            Logger.updateService.debug(
                "Checking updates for plugin: \(pluginId) (\(pluginSaveds.count) mangas)")
            // Get the plugin
            guard let plugin = PluginService.shared.getPlugin(pluginId) else {
                Logger.updateService.warning("Plugin not found: \(pluginId)")
                continue  // Skip if plugin doesn't exist
            }

            guard plugin.canUpdate else {
                Logger.updateService.debug("Skipping plugin without update support: \(pluginId)")
                continue
            }

            let mangaIds = pluginSaveds.map { $0.mangaId }

            let cachedMangaModels =
                try await DbService.shared.appDb?
                .read { db in
                    try MangaModel.filter(
                        mangaIds.contains(Column("mangaId")) && Column("pluginId") == pluginId
                    )
                    .fetchAll(db)
                } ?? []
            var cachedMangas: [String: Manga] = [:]
            for mangaModel in cachedMangaModels {
                guard let data = mangaModel.info.data(using: .utf8),
                    let manga = try? JSONDecoder().decode(Manga.self, from: data)
                else { continue }
                cachedMangas[mangaModel.mangaId] = manga
            }

            var hydrationIds: [String] = []
            var updateRequests: [MangaUpdateRequest] = []
            let usesCustomUpdates = plugin.supports(.mangaUpdates)
            for saved in pluginSaveds {
                let latestChapter = try? Chapter.decode(saved.latestChapter)
                if let latestChapter {
                    updateRequests.append(
                        MangaUpdateRequest(id: saved.mangaId, latestChapter: latestChapter))
                }

                if (usesCustomUpdates && cachedMangas[saved.mangaId] == nil) || latestChapter == nil
                {
                    hydrationIds.append(saved.mangaId)
                }
            }

            var resolvedMangas: [String: Manga] = [:]
            var updatePatchIds: Set<String> = []
            var patchedLatestChapters: [String: Chapter] = [:]
            var unresolvedHydrationIds = Set(hydrationIds)
            var pluginHadError = false

            // Hydrate manga
            if !hydrationIds.isEmpty, plugin.supports(.batchMangas) {
                do {
                    let mangas = try await plugin.getMangas(hydrationIds)
                    for manga in mangas where unresolvedHydrationIds.contains(manga.id) {
                        resolvedMangas[manga.id] = manga
                        unresolvedHydrationIds.remove(manga.id)
                    }
                } catch {
                    pluginHadError = true
                    Logger.updateService.error(
                        "Failed to hydrate manga snapshots in a batch for plugin \(pluginId)",
                        error: error)
                }
            }

            if !unresolvedHydrationIds.isEmpty, plugin.supports(.mangaDetails) {
                for mangaId in hydrationIds where unresolvedHydrationIds.contains(mangaId) {
                    do {
                        let manga = try await plugin.getDetailedManga(mangaId).toManga()
                        resolvedMangas[mangaId] = manga
                        unresolvedHydrationIds.remove(mangaId)
                    } catch {
                        pluginHadError = true
                        Logger.updateService.error(
                            "Failed to hydrate manga snapshot \(mangaId) for plugin \(pluginId)",
                            error: error)
                    }
                }
            }

            if !unresolvedHydrationIds.isEmpty {
                Logger.updateService.warning(
                    "Could not hydrate \(unresolvedHydrationIds.count) manga snapshots for plugin \(pluginId)"
                )
            }

            // Update manga
            if !updateRequests.isEmpty {
                do {
                    let requestIds = Set(updateRequests.map(\.id))
                    let patches = try await plugin.getMangaUpdates(updateRequests)
                    for patch in patches {
                        guard requestIds.contains(patch.id) else {
                            Logger.updateService.warning(
                                "Ignoring manga update patch for unexpected ID \(patch.id) from plugin \(pluginId)"
                            )
                            continue
                        }

                        updatePatchIds.insert(patch.id)
                        if let latestChapter = patch.latestChapter {
                            patchedLatestChapters[patch.id] = latestChapter
                        }

                        guard var manga = resolvedMangas[patch.id] ?? cachedMangas[patch.id] else {
                            if !usesCustomUpdates { resolvedMangas[patch.id] = patch }
                            continue
                        }

                        if let title = patch.title { manga.title = title }
                        if let cover = patch.cover { manga.cover = cover }
                        if let status = patch.status { manga.status = status }
                        if let latestChapter = patch.latestChapter {
                            manga.latestChapter = latestChapter
                        }
                        if let meta = patch.meta { manga.meta = meta }
                        resolvedMangas[patch.id] = manga
                    }
                } catch {
                    pluginHadError = true
                    Logger.updateService.error(
                        "Failed to check manga updates for plugin \(pluginId)", error: error)
                }
            }

            let savedsByMangaId = Dictionary(
                uniqueKeysWithValues: pluginSaveds.map { ($0.mangaId, $0) })

            for mangaId in updatePatchIds {
                guard var saved = savedsByMangaId[mangaId] else { continue }
                if let latestChapter = patchedLatestChapters[mangaId] {
                    saved.latestChapter = latestChapter.encode()
                }
                saved.datetime = Date()
                saved.updates = true
                updatedSaveds.append(saved)
                Logger.updateService.info(
                    "Plugin reported an update for manga: \(mangaId) (Plugin: \(pluginId))")
            }

            for (mangaId, manga) in resolvedMangas {
                if let data = try? JSONEncoder().encode(manga),
                    let info = String(data: data, encoding: .utf8)
                {
                    updatedMangaModels.append(
                        MangaModel(mangaId: mangaId, pluginId: pluginId, info: info))
                }

                if updatePatchIds.contains(mangaId) { continue }

                // A custom updater alone decides which manga are marked as updated.
                // Hydration only supplies a local snapshot for applying patches.
                if usesCustomUpdates { continue }

                guard var saved = savedsByMangaId[mangaId] else { continue }
                guard let latestChapter = manga.latestChapter else { continue }

                if let previousChapter = try? Chapter.decode(saved.latestChapter) {
                    guard latestChapter.id != previousChapter.id else { continue }
                    saved.datetime = Date()
                    saved.updates = true
                    saved.latestChapter = latestChapter.encode()
                    updatedSaveds.append(saved)
                    Logger.updateService.info(
                        "Found update for manga: \(mangaId) (Plugin: \(pluginId))")
                } else {
                    Logger.updateService.debug(
                        "Initialized latest chapter snapshot for manga: \(mangaId) (Plugin: \(pluginId))"
                    )
                }
            }

            if pluginHadError, case .online = Reach().connectionStatus() {
                let message = String(localized: "failedToCheckUpdatesForPluginFormat")
                NotificationService.shared.showWarning(String(format: message, pluginId))
            }
        }

        // Batch update all changed saveds and mangas
        _ = try await SavedService.shared.batchUpdate(
            saveds: updatedSaveds, mangas: updatedMangaModels)
        if !updatedSaveds.isEmpty {
            Logger.updateService.info(
                "Batch updating \(updatedSaveds.count) saveds and \(updatedMangaModels.count) mangas"
            )
            do { try await SyncService.shared.sync() } catch {
                Logger.updateService.error("Sync failed after update", error: error)
            }
        } else {
            Logger.updateService.debug("No updates found")
        }

        // Update last update time
        UserDefaults.standard.set(Date(), forKey: "UpdateService.lastUpdateTime")

        await MainActor.run { self.objectWillChange.send() }
        Logger.updateService.debug("Update process completed")
    }
}
