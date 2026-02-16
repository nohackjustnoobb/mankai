//
//  CacheWrapper.swift
//  mankai
//
//  Created by Travis XU on 16/2/2026.
//

import Foundation

private enum CacheMethod: String {
    case getSuggestion
    case search
    case getList
    case getDetailedManga
    case getChapter
    case getImage
}

private struct CacheEntry {
    let data: Any
    let expiryTime: Date

    var isExpired: Bool {
        return Date() > expiryTime
    }
}

/// Maximum number of cache entries before triggering cleanup of expired entries
private let maxCacheSize: Int = 100

class CacheWrapper: Plugin {
    private static let pruningLock = NSLock()
    private static var lastPruneCheck: Date = .distantPast

    private let plugin: Plugin

    // MARK: - Cache Properties

    private var cache: [String: CacheEntry] = [:]
    private let cacheLock = NSRecursiveLock()

    // MARK: - Init

    init(plugin: Plugin) {
        // We set the wrapped plugin heavily relying on delegation
        self.plugin = plugin
        super.init()
        Logger.cacheWrapper.debug("Initialized CacheWrapper for plugin: \(plugin.id)")
    }

    // MARK: - Metadata Delegation

    override var id: String {
        plugin.id
    }

    override var name: String? {
        plugin.name
    }

    override var version: String? {
        plugin.version
    }

    override var description: String? {
        plugin.description
    }

    override var authors: [String] {
        plugin.authors
    }

    override var repository: String? {
        plugin.repository
    }

    override var availableGenres: [Genre] {
        plugin.availableGenres
    }

    override var configs: [Config] {
        plugin.configs
    }

    override var tags: [String] {
        plugin.tags
    }

    override var shouldSync: Bool {
        plugin.shouldSync
    }

    // MARK: - Configs Delegation

    override var configValues: [ConfigValue] {
        plugin.configValues
    }

    override func getConfig(_ key: String) -> Any {
        return plugin.getConfig(key)
    }

    override func setConfig(key: String, value: Any) throws {
        try plugin.setConfig(key: key, value: value)
    }

    override func resetConfigs() throws {
        try plugin.resetConfigs()
    }

    // MARK: - Methods Delegation (Non-cached)

    override func savePlugin() throws {
        try plugin.savePlugin()
    }

    override func deletePlugin() throws {
        try plugin.deletePlugin()
    }

    override func isOnline() async throws -> Bool {
        return try await plugin.isOnline()
    }

    override func getMangas(_ ids: [String]) async throws -> [Manga] {
        return try await plugin.getMangas(ids)
    }

    // MARK: - Caching Logic

    private func getInMemoryCacheExpiryDuration() -> TimeInterval {
        let duration = UserDefaults.standard.double(forKey: SettingsKey.inMemoryCacheExpiryDuration.rawValue)
        return duration > 0 ? duration : SettingsDefaults.inMemoryCacheExpiryDuration.rawValue
    }

    private func getDiskCacheSizeLimit() -> Int64 {
        let limitRaw = UserDefaults.standard.integer(forKey: SettingsKey.diskCacheSizeLimit.rawValue)
        let limit = DiskCacheLimit(rawValue: limitRaw) ?? SettingsDefaults.diskCacheSizeLimit
        return Int64(limit.rawValue) * 1024 * 1024
    }

    private func manageDiskCacheSize() {
        guard CacheWrapper.pruningLock.try() else {
            return
        }
        defer { CacheWrapper.pruningLock.unlock() }

        // Only scan at most once per 3 minutes to avoid excessive I/O
        let now = Date()
        guard now.timeIntervalSince(CacheWrapper.lastPruneCheck) > 180 else {
            return
        }
        CacheWrapper.lastPruneCheck = now

        let fileManager = FileManager.default
        guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }

        let limit = getDiskCacheSizeLimit()

        do {
            let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
            let enumerator = fileManager.enumerator(
                at: cacheDir,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            )!

            var fileURLs: [URL] = []
            var totalSize: Int64 = 0

            for case let fileURL as URL in enumerator {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                      let isDirectory = resourceValues.isDirectory,
                      !isDirectory,
                      let fileSize = resourceValues.fileSize
                else { continue }

                totalSize += Int64(fileSize)
                if let _ = resourceValues.contentModificationDate {
                    fileURLs.append(fileURL)
                }
            }

            if totalSize > limit {
                // Sort by modification date (oldest first)
                fileURLs.sort { url1, url2 in
                    let d1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    let d2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    return d1 < d2
                }

                var currentSize = totalSize
                let targetSize = Int64(Double(limit) * 0.5)

                for fileURL in fileURLs {
                    if currentSize <= targetSize { break }

                    if let resources = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                       let fileSize = resources.fileSize
                    {
                        do {
                            try fileManager.removeItem(at: fileURL)
                            currentSize -= Int64(fileSize)
                            Logger.cacheWrapper.debug("Pruned cache file: \(fileURL.lastPathComponent)")
                        } catch {
                            Logger.cacheWrapper.error("Failed to prune cache file: \(error)")
                        }
                    }
                }
            }
        }
    }

    private func getCacheKey(for method: CacheMethod, with parameters: [String]) -> String {
        // URL-encode parameters to handle special characters
        let encodedParams = parameters.map { param in
            param.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? param
        }
        let paramString = encodedParams.joined(separator: "+")
        return "\(id)+\(method.rawValue)+\(paramString)"
    }

    private func getCachedData<T>(for key: String, as _: T.Type) -> T? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        // Periodically clear expired cache entries
        if cache.count > maxCacheSize {
            clearExpiredCache()
        }

        guard let entry = cache[key], !entry.isExpired else {
            Logger.cacheWrapper.debug("Cache miss for key: \(key)")
            removeExpiredEntry(for: key)
            return nil
        }

        Logger.cacheWrapper.debug("Cache hit for key: \(key)")
        return entry.data as? T
    }

    private func removeExpiredEntry(for key: String) {
        Task(priority: .background) { [weak self] in
            self?.performRemoveExpiredEntry(for: key)
        }
    }

    private func performRemoveExpiredEntry(for key: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        cache.removeValue(forKey: key)
    }

    private func setCachedData(_ data: Any, for key: String) {
        Task(priority: .background) { [weak self] in
            self?.performSetCachedData(data, for: key)
        }
    }

    private func performSetCachedData(_ data: Any, for key: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        Logger.cacheWrapper.debug("Setting cache for key: \(key)")
        let expiryTime = Date().addingTimeInterval(getInMemoryCacheExpiryDuration())
        cache[key] = CacheEntry(data: data, expiryTime: expiryTime)
    }

    private func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        Logger.cacheWrapper.info("Clearing all in-memory cache")
        cache.removeAll()
    }

    private func clearExpiredCache() {
        Task(priority: .background) { [weak self] in
            self?.performClearExpiredCache()
        }
    }

    private func performClearExpiredCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        Logger.cacheWrapper.info("Clearing expired in-memory cache")
        cache = cache.filter { _, entry in !entry.isExpired }
    }

    func clearAllCache() {
        clearCache()
    }

    // MARK: - Methods (Cached)

    override func getSuggestions(_ query: String) async throws -> [String] {
        let cacheKey = getCacheKey(for: .getSuggestion, with: [query])
        if let cachedSuggestions = getCachedData(for: cacheKey, as: [String].self) {
            return cachedSuggestions
        }

        let suggestions = try await plugin.getSuggestions(query)
        setCachedData(suggestions, for: cacheKey)
        return suggestions
    }

    override func search(_ query: String, page: UInt) async throws -> [Manga] {
        let cacheKey = getCacheKey(for: .search, with: [query, String(page)])
        if let cachedMangas = getCachedData(for: cacheKey, as: [Manga].self) {
            return cachedMangas
        }

        let mangas = try await plugin.search(query, page: page)
        setCachedData(mangas, for: cacheKey)
        return mangas
    }

    override func getList(page: UInt, genre: Genre, status: Status) async throws -> [Manga] {
        let cacheKey = getCacheKey(
            for: .getList, with: [String(page), genre.rawValue, String(status.rawValue)]
        )
        if let cachedMangas = getCachedData(for: cacheKey, as: [Manga].self) {
            return cachedMangas
        }

        let mangas = try await plugin.getList(page: page, genre: genre, status: status)
        setCachedData(mangas, for: cacheKey)
        return mangas
    }

    override func getDetailedManga(_ id: String) async throws -> DetailedManga {
        let cacheKey = getCacheKey(for: .getDetailedManga, with: [id])
        if let cachedDetailedManga = getCachedData(for: cacheKey, as: DetailedManga.self) {
            return cachedDetailedManga
        }

        let detailedManga = try await plugin.getDetailedManga(id)
        setCachedData(detailedManga, for: cacheKey)
        return detailedManga
    }

    override func getChapter(manga: DetailedManga, chapter: Chapter) async throws -> [String] {
        let cacheKey = getCacheKey(for: .getChapter, with: [manga.id, chapter.id])
        if let cachedImages = getCachedData(for: cacheKey, as: [String].self) {
            return cachedImages
        }

        let images = try await plugin.getChapter(manga: manga, chapter: chapter)
        setCachedData(images, for: cacheKey)
        return images
    }

    override func getImage(_ url: String) async throws -> Data {
        let cacheKey = getCacheKey(for: .getImage, with: [url])
        Logger.cacheWrapper.debug("Checking disk cache for image: \(url)")

        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!

        let pluginCacheDir = cacheDir.appendingPathComponent(id)
        if !fileManager.fileExists(atPath: pluginCacheDir.path) {
            try? fileManager.createDirectory(
                at: pluginCacheDir, withIntermediateDirectories: true, attributes: nil
            )
        }

        // Try to read from disk cache
        let imageCacheFile = pluginCacheDir.appendingPathComponent(cacheKey)
        if fileManager.fileExists(atPath: imageCacheFile.path) {
            if let data = try? Data(contentsOf: imageCacheFile) {
                Logger.cacheWrapper.debug("Disk cache hit for image: \(url)")
                return data
            }
        }

        // Fetch from plugin
        Logger.cacheWrapper.debug("Disk cache miss for image: \(url). Fetching from plugin.")
        let data = try await plugin.getImage(url)

        // Write to disk cache
        try? data.write(to: imageCacheFile)
        Logger.cacheWrapper.debug("Wrote image to disk cache: \(url)")

        // Check and enforce disk cache limit
        Task(priority: .background) { [weak self] in
            self?.manageDiskCacheSize()
        }

        return data
    }
}
