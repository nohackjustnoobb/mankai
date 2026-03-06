//
//  SyncService.swift
//  mankai
//
//  Created by Travis XU on 20/7/2025.
//

import Combine
import Foundation
import GRDB

class SyncService: ObservableObject {
    /// The shared singleton instance of SyncService.
    static let shared = SyncService()
    /// The list of available synchronization engines.
    static let engines: [SyncEngine] =
        [HttpEngine.shared, SupabaseEngine.shared]

    private init() {
        Logger.syncService.debug("Initializing SyncService")
        let defaults = UserDefaults.standard
        if let engineId = defaults.string(forKey: "SyncService.engineId") {
            _engine = SyncService.engines.first(where: { $0.id == engineId })
            subscribeToEngine()
            startPeriodicSync()
        }
    }

    private var _engine: SyncEngine?
    private var engineCancellable: AnyCancellable?
    private var syncTimer: Timer?
    private var syncTask: Task<Void, Error>?
    private let syncInterval: TimeInterval = 60 * 3 // 3 minutes

    /// A flag indicating if a synchronization process is currently in progress.
    @Published var isSyncing = false

    /// The currently active synchronization engine.
    var engine: SyncEngine? {
        get {
            _engine
        }
        set {
            Logger.syncService.debug("Setting sync engine: \(newValue?.id ?? "nil")")
            _engine = newValue

            let defaults = UserDefaults.standard
            defaults.setValue(newValue?.id, forKey: "SyncService.engineId")

            subscribeToEngine()

            if newValue != nil {
                startPeriodicSync()
            } else {
                stopPeriodicSync()
            }

            DispatchQueue.main.async {
                self.objectWillChange.send()
            }

            Task {
                try? await self.onEngineChange()
            }
        }
    }

    /// The timestamp of the last successful synchronization.
    var lastSyncTime: Date? {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "SyncService.lastSyncTime") as? Date
    }

    /// Handles changes when the sync engine is updated.
    /// - Throws: An error if the new engine cannot be initialized.
    func onEngineChange() async throws {
        Logger.syncService.debug("Handling engine change")
        guard let engine = engine else { return }

        // Reset last sync time in UserDefaults
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "SyncService.lastSyncTime")
        defaults.set(true, forKey: "SyncService.initialSync")

        try await engine.onSelected()
        try await sync()
        try await UpdateService.shared.update()
    }

    private func subscribeToEngine() {
        engineCancellable?.cancel()
        engineCancellable = engine?.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }
    }

    private func startPeriodicSync() {
        stopPeriodicSync()

        guard engine != nil else { return }

        // Initial
        Logger.syncService.debug("Starting periodic sync")
        Task {
            try? await sync()
            try? await UpdateService.shared.update()
        }

        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) {
            [weak self] _ in
            Task {
                try? await self?.sync()
            }
        }
    }

    private func stopPeriodicSync() {
        Logger.syncService.debug("Stopping periodic sync")
        syncTimer?.invalidate()
        syncTimer = nil
    }

    deinit {
        stopPeriodicSync()
        engineCancellable?.cancel()
    }

    /// Triggers a synchronization process.
    /// - Parameter wait: If true, waits for an ongoing sync to complete before proceeding (or skipping).
    /// - Throws: An error if the synchronization fails.
    func sync(wait: Bool = false, showError: Bool = true) async throws {
        let (task, wasAlreadyRunning) = await MainActor.run { () -> (Task<Void, Error>, Bool) in
            if let current = syncTask {
                return (current, true)
            }

            isSyncing = true
            let newTask = Task {
                defer {
                    Task { @MainActor in
                        self.isSyncing = false
                        self.syncTask = nil
                    }
                }
                try await internalSync()
            }
            syncTask = newTask
            return (newTask, false)
        }

        if wasAlreadyRunning {
            if !wait {
                Logger.syncService.debug("Sync already in progress, skipping")
                return
            }
            Logger.syncService.debug("Waiting for ongoing sync to complete")
        }

        do {
            try await task.value
        } catch {
            Logger.syncService.error("Sync failed: \(error)")

            if showError, case .online = Reach().connectionStatus() {
                let message = String(localized: "failedToSync")
                NotificationService.shared.showWarning(String(format: message, error.localizedDescription))
            }

            throw error
        }

        if wasAlreadyRunning {
            Logger.syncService.debug("Ongoing sync completed, proceeding")
        }
    }

    private func internalSync() async throws {
        Logger.syncService.debug("Starting sync")
        guard let engine = engine else {
            Logger.syncService.error("No sync engine available")
            throw NSError(
                domain: "SyncService", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "noSyncEngine")]
            )
        }

        if UserDefaults.standard.bool(forKey: "SyncService.initialSync") {
            try await engine.initialSync()
            UserDefaults.standard.set(false, forKey: "SyncService.initialSync")
        }

        try await engine.sync()

        // Update sync time
        UserDefaults.standard.set(Date(), forKey: "SyncService.lastSyncTime")

        await MainActor.run {
            self.objectWillChange.send()
        }
        Logger.syncService.debug("Sync completed")
    }

    func addSaveds(_ saveds: [SavedModel]) async throws {
        guard let engine = engine else {
            Logger.syncService.error("No sync engine available")
            throw NSError(
                domain: "SyncService", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "noSyncEngine")]
            )
        }

        try await engine.addSaveds(saveds)
    }

    func addSaved(_ saved: SavedModel) async throws {
        try await addSaveds([saved])
    }

    func removeSaveds(_ saveds: [(mangaId: String, pluginId: String)]) async throws {
        guard let engine = engine else {
            Logger.syncService.error("No sync engine available")
            throw NSError(
                domain: "SyncService", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "noSyncEngine")]
            )
        }

        try await engine.removeSaveds(saveds)
    }

    func removeSaved(mangaId: String, pluginId: String) async throws {
        try await removeSaveds([(mangaId: mangaId, pluginId: pluginId)])
    }
}
