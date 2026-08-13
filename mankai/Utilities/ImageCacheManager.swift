//
//  ImageCacheManager.swift
//  mankai
//
//  Created by Travis XU on 6/8/2026.
//

import Foundation

final class ImageCacheManager: @unchecked Sendable {
    static let shared = ImageCacheManager()

    private let regularCacheDirectory: URL?
    private let requestRegistry = AsyncLoadRegistry<Data>()
    private let pruningTimer: DispatchSourceTimer

    private init() {
        regularCacheDirectory = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(CacheDirectory.regular)

        let timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "com.mankai.image-cache", qos: .background)
        )
        pruningTimer = timer
        timer.schedule(deadline: .now(), repeating: .seconds(180))
        timer.setEventHandler { [weak self] in
            self?.pruneIfNeeded()
        }
        timer.resume()
    }

    deinit {
        pruningTimer.cancel()
    }

    func image(
        for key: String,
        pluginID: String,
        load: @escaping () async throws -> Data
    ) async throws -> Data {
        if let data = cachedImage(for: key, pluginID: pluginID) {
            Logger.cacheWrapper.debug("Disk cache hit for image key: \(key)")
            return data
        }

        let requestKey = "\(pluginID)+\(key)"
        return try await requestRegistry.value(for: requestKey) { [self] in
            if let data = cachedImage(for: key, pluginID: pluginID) {
                Logger.cacheWrapper.debug("Disk cache hit for image key: \(key)")
                return data
            }

            Logger.cacheWrapper.debug("Disk cache miss for image key: \(key)")
            let data = try await load()
            cacheImage(data, for: key, pluginID: pluginID)
            return data
        }
    }

    private func cachedImage(for key: String, pluginID: String) -> Data? {
        guard let regularCacheDirectory else {
            return nil
        }

        let fileURL =
            regularCacheDirectory
            .appendingPathComponent(pluginID)
            .appendingPathComponent(key)
        return try? Data(contentsOf: fileURL)
    }

    private func cacheImage(_ data: Data, for key: String, pluginID: String) {
        guard let regularCacheDirectory else {
            return
        }
        let pluginCacheDirectory = regularCacheDirectory.appendingPathComponent(pluginID)

        do {
            try FileManager.default.createDirectory(
                at: pluginCacheDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(
                to: pluginCacheDirectory.appendingPathComponent(key),
                options: .atomic
            )
            Logger.cacheWrapper.debug("Wrote image to disk cache for key: \(key)")
        } catch {
            Logger.cacheWrapper.error("Failed to write image to disk cache: \(error)")
        }
    }

    private func diskCacheSizeLimit() -> Int64 {
        let limitRaw = UserDefaults.standard.integer(
            forKey: SettingsKey.diskCacheSizeLimit.rawValue)
        let limit = DiskCacheLimit(rawValue: limitRaw) ?? SettingsDefaults.diskCacheSizeLimit
        return Int64(limit.rawValue) * 1024 * 1024
    }

    private func pruneIfNeeded() {
        Logger.cacheWrapper.debug("Checking disk cache size")

        guard let regularCacheDirectory else {
            Logger.cacheWrapper.debug("Skipping disk cache pruning: cache directory unavailable")
            return
        }

        let limit = diskCacheSizeLimit()

        // Avoid collecting and sorting file metadata while the cache is within its limit.
        guard
            let totalSizeRaw = try? FileManager.default.allocatedSizeOfDirectory(
                at: regularCacheDirectory)
        else {
            Logger.cacheWrapper.error("Failed to measure disk cache size")
            return
        }
        let totalSize = Int64(totalSizeRaw)
        Logger.cacheWrapper.debug("Disk cache size: \(totalSize) bytes, limit: \(limit) bytes")

        guard totalSize > limit else {
            Logger.cacheWrapper.debug("Skipping disk cache pruning: cache is within its limit")
            return
        }

        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey, .contentModificationDateKey, .fileSizeKey,
        ]
        let enumerator = FileManager.default.enumerator(
            at: regularCacheDirectory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        )!

        var fileURLs: [URL] = []

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                let isDirectory = resourceValues.isDirectory,
                !isDirectory,
                resourceValues.contentModificationDate != nil
            else { continue }

            fileURLs.append(fileURL)
        }

        Logger.cacheWrapper.debug(
            "Disk cache exceeds its limit, found \(fileURLs.count) files to consider for pruning")

        fileURLs.sort { url1, url2 in
            let d1 =
                (try? url1.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? Date.distantPast
            let d2 =
                (try? url2.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? Date.distantPast
            return d1 < d2
        }

        var currentSize = totalSize
        let targetSize = Int64(Double(limit) * 0.5)
        var prunedFileCount = 0

        for fileURL in fileURLs {
            if currentSize <= targetSize { break }

            if let resources = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                let fileSize = resources.fileSize
            {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    currentSize -= Int64(fileSize)
                    prunedFileCount += 1
                    Logger.cacheWrapper.debug("Pruned cache file: \(fileURL.lastPathComponent)")
                } catch {
                    Logger.cacheWrapper.error("Failed to prune cache file: \(error)")
                }
            }
        }

        Logger.cacheWrapper.debug(
            "Finished disk cache pruning: removed \(prunedFileCount) files, current size: \(currentSize) bytes"
        )
    }
}
