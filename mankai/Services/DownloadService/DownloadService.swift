//
//  DownloadService.swift
//  mankai
//
//  Created by Travis XU on 13/2/2026.
//

import Foundation
import GRDB

enum DownloadStatus {
    case queued
    case downloading(progress: Double)
    case completed
    case failed(error: Error)
    case cancelled
}

final class DownloadTask: Identifiable, ObservableObject {
    let id: String
    let manga: DownloadMangaModel

    @Published var status: DownloadStatus = .queued

    init(manga: DownloadMangaModel, save: Bool = true) async throws {
        id = UUID().uuidString
        self.manga = manga

        if save {
            try await self.save()
        }
    }

    static func restoreUnfinishedTasks() async throws -> [DownloadTask] {
        guard let db = DownloadPlugin.shared.db else {
            return []
        }

        let unfinishedMangas = try await db.read { db in
            try DownloadMangaModel
                .filter(Column("downloaded") == false)
                .fetchAll(db)
        }

        var restoredTasks: [DownloadTask] = []
        for manga in unfinishedMangas {
            let task = try await DownloadTask(manga: manga, save: false)
            restoredTasks.append(task)
        }

        return restoredTasks
    }

    func download() async throws {
        await MainActor.run {
            status = .downloading(progress: 0.0)
        }

        // 1. Get Source Plugin
        guard let plugin = PluginService.shared.getPlugin(manga.pluginId) else {
            Logger.downloadService.error("Plugin not found: \(manga.pluginId)")
            throw MankaiErrorCode.downloadPluginNotFound.makeError()
        }

        guard plugin.supportsDownloads else {
            Logger.downloadService.warning("Downloads are disabled for plugin: \(plugin.id)")
            throw MankaiErrorCode.downloadDisabled.makeError()
        }

        // 2. Download Cover
        if let coverUrl = manga.cover {
            do {
                if try await !DownloadPlugin.shared.isImageDownloaded(coverUrl) {
                    let data = try await plugin.getImage(coverUrl)
                    try await DownloadPlugin.shared.saveImage(
                        url: coverUrl, data: data, mangaId: manga.id
                    )
                }
            } catch {
                Logger.downloadService.warning("Failed to download cover: \(error)")
            }
        }

        // 3. Process Chapters
        let detailedManga = try await DownloadPlugin.shared.getDetailedManga(manga.id)

        var chaptersToDownload: [Chapter] = []
        if let chaptersJson = manga.chapters,
            let chaptersData = chaptersJson.data(using: .utf8),
            let chapterGroups = try? JSONDecoder().decode(ChapterGroups.self, from: chaptersData)
        {
            chaptersToDownload = chapterGroups.flatMap(\.chapters)
        }

        let totalChapters = Double(chaptersToDownload.count)
        var downloadedChaptersCount = 0.0

        for chapter in chaptersToDownload {
            if case .cancelled = status { return }

            var chapterUrls: [String] = []
            var isNewChapter = false

            // Check if chapter exists locally
            do {
                chapterUrls = try await DownloadPlugin.shared.getChapter(
                    manga: detailedManga, chapter: chapter
                )
            } catch {
                // Not found, fetch from source
                chapterUrls = try await plugin.getChapter(
                    manga: detailedManga, chapter: chapter
                )
                isNewChapter = true
            }

            // Save chapter if it's new
            if isNewChapter {
                let chapterModel = DownloadChapterModel(
                    mangaId: manga.id,
                    chapterId: chapter.id,
                    urls: chapterUrls.joined(separator: "|"),
                    downloaded: false
                )
                try await DownloadPlugin.shared.saveChapter(chapterModel)
            }

            // Download images
            let totalPages = Double(chapterUrls.count)
            if totalPages > 0 {
                for (index, url) in chapterUrls.enumerated() {
                    if case .cancelled = status { return }

                    if try await !DownloadPlugin.shared.isImageDownloaded(url) {
                        let data = try await plugin.getImage(url)
                        try await DownloadPlugin.shared.saveImage(
                            url: url, data: data, mangaId: manga.id
                        )
                    }

                    let currentProgress =
                        (downloadedChaptersCount + (Double(index + 1) / totalPages))
                        / totalChapters
                    await MainActor.run {
                        status = .downloading(progress: currentProgress)
                    }
                }
            }

            // Mark chapter as downloaded
            let completedChapterModel = DownloadChapterModel(
                mangaId: manga.id,
                chapterId: chapter.id,
                urls: chapterUrls.joined(separator: "|"),
                downloaded: true
            )
            try await DownloadPlugin.shared.saveChapter(completedChapterModel)

            downloadedChaptersCount += 1.0
            let finalProgress = downloadedChaptersCount / totalChapters
            await MainActor.run {
                status = .downloading(
                    progress: finalProgress
                )
            }
        }

        // Mark manga as downloaded
        var completedManga = manga
        completedManga.downloaded = true
        try await DownloadPlugin.shared.saveManga(completedManga)

        await MainActor.run {
            status = .completed
        }
    }

    func cancel() async throws {
        await MainActor.run {
            status = .cancelled
        }

        try await delete()
    }

    func markFailed(error: Error) async throws {
        await MainActor.run {
            status = .failed(error: error)
        }

        try await delete()
    }

    func retry() async throws {
        try await save()

        await MainActor.run {
            status = .queued
        }
    }

    func save() async throws {
        try await DownloadPlugin.shared.saveManga(manga)
    }

    func delete() async throws {
        try await DownloadPlugin.shared.deleteManga(manga.id)
    }
}

final class DownloadService: ObservableObject {
    /// The shared singleton instance of DownloadService.
    static let shared = DownloadService()

    @Published var tasks: [String: DownloadTask] = [:]

    private init() {
        Logger.downloadService.debug("Initializing DownloadService")

        Task {
            Logger.downloadService.debug("Restoring unfinished tasks")
            do {
                let unfinishedTasks = try await DownloadTask.restoreUnfinishedTasks()
                await MainActor.run {
                    tasks = unfinishedTasks.reduce(into: [:]) { result, task in
                        result[task.id] = task
                    }
                    self.scheduleDownloads()
                }
            } catch {
                Logger.downloadService.error("Failed to restore unfinished tasks: \(error)")
            }
        }
    }

    func queue(plugin: Plugin, manga: DetailedManga, chapters: ChapterGroups) async throws
        -> DownloadTask
    {
        let chaptersCount = chapters.flatMap(\.chapters).count
        Logger.downloadService.debug(
            "Queuing download for \(manga.title ?? manga.id), \(chaptersCount) chapters")

        guard plugin.supportsDownloads else {
            Logger.downloadService.warning("Downloads are disabled for plugin: \(plugin.id)")
            throw MankaiErrorCode.downloadDisabled.makeError()
        }

        guard let db = DownloadPlugin.shared.db else {
            Logger.downloadService.error("Download database not available")
            throw MankaiErrorCode.downloadDatabaseNotAvailable.makeError()
        }

        // Create the combined ID (pluginId+mangaId)
        let combinedId = "\(plugin.id)+\(manga.id)"

        // Merge chapters: start with new chapters, then add old chapters if they exist
        var finalChapters = chapters

        // Check if manga exists and get old chapters
        if let existingManga = try await db.read({ db in
            try DownloadMangaModel.fetchOne(db, key: combinedId)
        }) {
            Logger.downloadService.info("Found existing manga in database, merging chapters")

            // Parse existing chapters
            if let existingChaptersJson = existingManga.chapters,
                let chaptersData = existingChaptersJson.data(using: .utf8),
                let existingChapters = try? JSONDecoder().decode(
                    ChapterGroups.self, from: chaptersData)
            {
                for existingGroup in existingChapters {
                    guard
                        let currentIndex = finalChapters.firstIndex(where: {
                            $0.title == existingGroup.title
                        })
                    else {
                        finalChapters.append(existingGroup)
                        continue
                    }

                    // Merge lists, avoiding duplicates while retaining the selected order.
                    for existingChapter in existingGroup.chapters {
                        if !finalChapters[currentIndex].chapters.contains(where: {
                            $0.id == existingChapter.id
                        }) {
                            finalChapters[currentIndex].chapters.append(existingChapter)
                        }
                    }
                }
            }
        }

        let chaptersToPersist = finalChapters.map { group in
            ChapterGroup(
                title: group.title,
                chapters: group.chapters.map { chapter in
                    Chapter(id: chapter.id, title: chapter.title)
                }
            )
        }
        let chaptersJsonData = try JSONEncoder().encode(chaptersToPersist)
        let chaptersJson = String(data: chaptersJsonData, encoding: .utf8)

        var latestChapterJson: String?
        if let latestChapter = manga.latestChapter {
            var latestChapterDict: [String: Any] = ["id": latestChapter.id]
            if let title = latestChapter.title {
                latestChapterDict["title"] = title
            }
            let latestChapterData = try JSONSerialization.data(
                withJSONObject: latestChapterDict, options: [])
            latestChapterJson = String(data: latestChapterData, encoding: .utf8)
        }

        let mangaModel = DownloadMangaModel(
            pluginId: plugin.id,
            mangaId: manga.id,
            id: combinedId,
            title: manga.title,
            cover: manga.cover,
            status: manga.status != nil ? Int(manga.status!.rawValue) : nil,
            description: manga.description,
            updatedAt: manga.updatedAt,
            authors: manga.authors.joined(separator: "|"),
            genres: manga.genres.map { $0.rawValue }.joined(separator: "|"),
            latestChapter: latestChapterJson,
            chapters: chaptersJson,
            downloaded: false
        )

        let task = try await DownloadTask(manga: mangaModel)
        await MainActor.run {
            tasks[task.id] = task
            self.scheduleDownloads()
        }

        Logger.downloadService.info(
            "Successfully queued download task for \(manga.title ?? manga.id)")
        let message = String(localized: "downloadQueuedMessageFormat")
        NotificationService.shared.showInfo(String(format: message, manga.title ?? manga.id))

        return task
    }

    func cancelTask(id: String) async throws {
        if let task = tasks[id] {
            try await task.cancel()

            await MainActor.run {
                _ = tasks.removeValue(forKey: id)
            }

            Logger.downloadService.info("Cancelled task for \(task.manga.title ?? task.manga.id)")
        }
    }

    func retryTask(id: String) async throws {
        if let task = tasks[id] {
            try await task.retry()
            await MainActor.run {
                self.scheduleDownloads()
            }
        }
    }

    private var scheduleTask: Task<Void, Never>?

    func scheduleDownloads() {
        scheduleTask?.cancel()
        scheduleTask = Task { @MainActor in
            let tasks = self.tasks.values
            let groupedTasks = Dictionary(grouping: tasks, by: { $0.manga.pluginId })

            for (_, tasks) in groupedTasks {
                // Check if any task is currently downloading for this plugin
                let isDownloading = tasks.contains { task in
                    if case .downloading = task.status { return true }
                    return false
                }

                if isDownloading { break }

                // Find the first queued task
                if let nextTask = tasks.first(where: {
                    if case .queued = $0.status { return true }
                    return false
                }) {
                    self.startTask(nextTask)
                }
            }
        }
    }

    private func startTask(_ task: DownloadTask) {
        Task {
            do {
                try await task.download()

                Logger.downloadService.info(
                    "Successfully downloaded task for \(task.manga.title ?? task.manga.id)")
                let message = String(localized: "downloadCompletedMessageFormat")
                NotificationService.shared.showSuccess(
                    String(format: message, task.manga.title ?? task.manga.id))

                await MainActor.run {
                    _ = tasks.removeValue(forKey: task.id)
                }
            } catch {
                if case .cancelled = task.status {
                    // Already cancelled
                } else {
                    Logger.downloadService.error("Task failed: \(error)")
                    try? await task.markFailed(error: error)

                    let message = String(localized: "downloadFailedMessageFormat")
                    NotificationService.shared.showError(
                        String(
                            format: message,
                            task.manga.title ?? task.manga.id,
                            error.localizedDescription
                        )
                    )
                }
            }

            // Trigger scheduler again to pick up next task
            self.scheduleDownloads()
        }
    }
}
