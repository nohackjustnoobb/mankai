//
//  ReaderSession.swift
//  mankai
//
//  Created by Travis XU on 10/2/2026.
//

import Combine
import SwiftUI
import UIKit

enum ReaderImageState {
    case loading
    case success(UIImage)
    case failed
}

struct ReaderImage {
    let url: String
    var state: ReaderImageState
}

struct ReaderGroup: Identifiable, Hashable {
    let id = UUID()
    var urls: [String]

    func contains(_ url: String) -> Bool {
        return urls.contains(url)
    }
}

@MainActor
class ReaderSession: ObservableObject {
    @Published var images: [String: ReaderImage] = [:]
    @Published var groups: [ReaderGroup] = []
    private(set) var urls: [String] = []

    private let plugin: Plugin
    private let manga: DetailedManga
    private let downloadManga: DetailedManga?
    @Published private(set) var imageLayout: ImageLayout {
        didSet {
            groupImages()
        }
    }

    var readingDirection: ReadingDirection? {
        didSet {
            if oldValue != readingDirection {
                Logger.readerSession.debug("Reading direction changed to: \(readingDirection.map { "\($0)" } ?? "nil")")

                adjacencyTasks.values.forEach { $0.cancel() }
                adjacencyTasks.removeAll()

                checkedPairs = []
                adjacencyScores = [:]

                groupImages()
                triggerAdjacencyChecks()
            }
        }
    }

    private var loadingTasks: [String: Task<Void, Never>] = [:]
    private var retryCount: [String: Int] = [:]
    private let maxRetries = 3

    // Adjacency Checking
    private var adjacencyTasks: [String: Task<Void, Never>] = [:]
    private var checkedPairs: Set<String> = []
    private var adjacencyScores: [String: Double] = [:]
    var defaultGroupSize: Int {
        if readingDirection == .vertical { return 1 }

        switch imageLayout {
        case .auto:
            return UIApplication.windowBounds.width > UIApplication.windowBounds.height ? 2 : 1
        case .onePerRow:
            return 1
        case .twoPerRow:
            return 2
        }
    }

    private var useSmartGrouping: Bool {
        if readingDirection == .vertical { return false }
        return UserDefaults.standard.object(forKey: SettingsKey.useSmartGrouping.rawValue) as? Bool
            ?? SettingsDefaults.useSmartGrouping
    }

    private var smartGroupingSensitivity: Double {
        UserDefaults.standard.object(forKey: SettingsKey.smartGroupingSensitivity.rawValue) as? Double
            ?? SettingsDefaults.smartGroupingSensitivity
    }

    init(plugin: Plugin, manga: DetailedManga, downloadManga: DetailedManga?, readingDirection: ReadingDirection? = nil) {
        self.plugin = plugin
        self.manga = manga
        self.downloadManga = downloadManga
        self.readingDirection = readingDirection
        Logger.readerSession.debug("Initializing ReaderSession for manga: \(manga.title ?? manga.id)")

        // Initialize from UserDefaults
        let rawValue = UserDefaults.standard.integer(forKey: SettingsKey.imageLayout.rawValue)
        imageLayout = ImageLayout(rawValue: rawValue) ?? SettingsDefaults.imageLayout

        // Observe UserDefaults changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        // Observe orientation changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateGrouping),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func defaultsChanged() {
        let rawValue = UserDefaults.standard.integer(forKey: SettingsKey.imageLayout.rawValue)
        let newLayout = ImageLayout(rawValue: rawValue) ?? SettingsDefaults.imageLayout
        Task { @MainActor in
            if newLayout != imageLayout {
                self.imageLayout = newLayout
            } else {
                self.groupImages()
            }
        }
    }

    @objc func updateGrouping() {
        Task { @MainActor in
            groupImages()
        }
    }

    func getChapter(chapter: Chapter) async throws {
        Logger.readerSession.info("Loading chapter: \(chapter.title ?? chapter.id)")
        // Cancel all existing tasks
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()
        adjacencyTasks.values.forEach { $0.cancel() }
        adjacencyTasks.removeAll()

        // Reset state
        images = [:]
        groups = []
        urls = []
        retryCount = [:]
        checkedPairs = []
        adjacencyScores = [:]

        var urls: [String]?
        if let downloadManga = downloadManga {
            do {
                urls = try await DownloadPlugin.shared.getChapter(manga: downloadManga, chapter: chapter)
            } catch {
                Logger.readerSession.warning("Failed to load chapter from download: \(error)")
            }
        }

        if let urls = urls, !urls.isEmpty {
            self.urls = urls
        } else {
            self.urls = try await plugin.getChapter(manga: manga, chapter: chapter)
        }

        // Initialize images with loading state
        for url in self.urls {
            images[url] = ReaderImage(url: url, state: .loading)
        }

        // Initial grouping
        groupImages()

        loadImages(urls: self.urls)
    }

    private func loadImages(urls: [String]) {
        for url in urls {
            loadImage(url: url)
        }
    }

    private func loadImage(url: String) {
        Logger.readerSession.debug("Starting load for image: \(url)")
        let task = Task {
            let currentRetry = self.retryCount[url] ?? 0

            do {
                let imageData: Data
                if let downloaded = try? await DownloadPlugin.shared.isImageDownloaded(url), downloaded {
                    imageData = try await DownloadPlugin.shared.getImage(url)
                } else {
                    imageData = try await plugin.getImage(url)
                }

                if let image = UIImage(data: imageData) {
                    Logger.readerSession.debug("Successfully loaded image: \(url)")
                    self.images[url] = ReaderImage(url: url, state: .success(image))
                    self.groupImages()
                    self.triggerAdjacencyChecks()
                } else {
                    Logger.readerSession.error("Failed to decode image data for: \(url)")
                    await self.handleImageLoadFailure(url: url, currentRetry: currentRetry)
                }
            } catch {
                if !Task.isCancelled {
                    Logger.readerSession.error("Failed to load image: \(url)", error: error)
                    await self.handleImageLoadFailure(url: url, currentRetry: currentRetry)
                }
            }
        }

        loadingTasks[url] = task
    }

    private func handleImageLoadFailure(url: String, currentRetry: Int) async {
        if currentRetry < maxRetries {
            Logger.readerSession.warning("Retrying image load for \(url). Attempt: \(currentRetry + 1)")
            // Exponential backoff: 1s, 2s, 4s
            let delay = TimeInterval(1 << currentRetry)

            retryCount[url] = currentRetry + 1

            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            if !Task.isCancelled {
                loadImage(url: url)
            }
        } else {
            Logger.readerSession.error("Max retries reached for image: \(url)")
            images[url] = ReaderImage(url: url, state: .failed)
        }
    }

    private func groupImages() {
        Logger.readerSession.debug("Grouping images with layout: \(imageLayout), smartGrouping: \(useSmartGrouping)")
        var newGroups: [ReaderGroup] = []

        var i = 0
        while i < urls.count {
            let url = urls[i]
            let isWide = isImageWide(url: url)

            if isWide {
                // Wide images get their own group
                newGroups.append(ReaderGroup(urls: [url]))
                i += 1
            } else if i + 1 < urls.count {
                // Check for adjacency (smart grouping)
                let nextUrl = urls[i + 1]
                let pairKey = "\(url)|\(nextUrl)"

                if useSmartGrouping,
                   let score = adjacencyScores[pairKey],
                   score > (1 - smartGroupingSensitivity)
                {
                    // These two are a spread! Group them together.
                    newGroups.append(ReaderGroup(urls: [url, nextUrl]))
                    i += 2
                    continue
                }

                // Normal grouping logic
                var groupUrls: [String] = []
                var j = i

                while j < urls.count, groupUrls.count < defaultGroupSize {
                    let currentUrl = urls[j]

                    // If we encounter a wide image while building the group, stop here
                    if isImageWide(url: currentUrl) {
                        break
                    }

                    // If we encounter a start of a known spread (that isn't the first item in this group), stop
                    if j > i, j + 1 < urls.count {
                        let nextSpreadKey = "\(currentUrl)|\(urls[j + 1])"
                        if useSmartGrouping,
                           let score = adjacencyScores[nextSpreadKey],
                           score > (1 - smartGroupingSensitivity)
                        {
                            break
                        }
                    }

                    groupUrls.append(currentUrl)
                    j += 1
                }

                newGroups.append(ReaderGroup(urls: groupUrls))
                i = j
            } else {
                // Last single image
                newGroups.append(ReaderGroup(urls: [url]))
                i += 1
            }
        }

        groups = newGroups
        Logger.readerSession.debug("Grouping completed. Total groups: \(newGroups.count)")
    }

    private func triggerAdjacencyChecks() {
        guard useSmartGrouping, urls.count > 1, let readingDirection = readingDirection else { return }
        Logger.readerSession.debug("Triggering adjacency checks")

        // We only check pairs that are loaded and not yet checked
        let pairsToCheck: [(String, String, UIImage, UIImage)] = urls.indices.dropLast().compactMap { i in
            let u1 = urls[i]
            let u2 = urls[i + 1]
            let key = "\(u1)|\(u2)"

            if checkedPairs.contains(key) { return nil }

            if let img1 = images[u1], case let .success(ui1) = img1.state,
               let img2 = images[u2], case let .success(ui2) = img2.state
            {
                if readingDirection == .rightToLeft {
                    // RTL: u2 is physically Left, u1 is physically Right
                    return (u1, u2, ui2, ui1)
                } else {
                    // LTR: u1 is physically Left, u2 is physically Right
                    return (u1, u2, ui1, ui2)
                }
            }

            return nil
        }

        for (u1, u2, img1, img2) in pairsToCheck {
            let key = "\(u1)|\(u2)"
            checkedPairs.insert(key) // Mark as checked immediately so we don't queue it again

            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }

                do {
                    // Run model
                    let score = try AdjacencyModelWrapper.shared?.predict(image1: img1, image2: img2) ?? 0

                    await MainActor.run {
                        // Double check cancellation before applying side effects
                        guard !Task.isCancelled else { return }

                        Logger.readerSession.debug("Adjacency score for \(key): \(score)")

                        self.adjacencyScores[key] = score
                        if score > (1 - self.smartGroupingSensitivity) {
                            self.groupImages()
                        }
                    }
                } catch {
                    Logger.readerSession.error("Adjacency check failed for \(key)", error: error)
                }
            }

            adjacencyTasks[key] = task
        }
    }

    private func isImageWide(url: String) -> Bool {
        guard let readerImage = images[url], case let .success(image) = readerImage.state else {
            return false
        }

        return image.size.width > image.size.height
    }
}
