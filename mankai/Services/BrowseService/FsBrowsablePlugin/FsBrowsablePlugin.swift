//
//  FsBrowsablePlugin.swift
//  mankai
//
//  Created by Travis XU on 13/7/2026.
//

import CryptoKit
import Foundation
import GRDB
import SwiftUI

class FsBrowsablePlugin: Plugin, Browsable {
    override var id: String {
        _id
    }

    override var name: String? {
        dirName
    }

    override var availableGenres: [Genre] {
        Genre.allCases
    }

    var systemImageName: String {
        "folder.fill"
    }

    private static let systemImagePalette: [Color] = [
        .red, .orange, .yellow, .green, .mint,
        .teal, .cyan, .blue, .indigo, .purple,
        .pink, .brown,
    ]

    private lazy var _systemImageColor: Color = {
        var hash: UInt64 = 5381
        for byte in _id.utf8 {
            hash = (hash &<< 5) &+ hash &+ UInt64(byte)
        }
        let index = Int(hash % UInt64(FsBrowsablePlugin.systemImagePalette.count))
        return FsBrowsablePlugin.systemImagePalette[index]
    }()

    var systemImageColor: Color {
        _systemImageColor
    }

    var supportedExtensions: [String] {
        extensionsIndex.keys.map { $0 }
    }

    var importsPath: String {
        "imports"
    }

    private var importsDir: URL {
        url.appendingPathComponent(importsPath)
    }

    let url: URL
    private let _id: String
    private var _isAccessing: Bool = false
    private lazy var dirName: String = url.lastPathComponent
    private let parsers: [String: Parser]

    /// On-disk cache of parsed manga (JSON-encoded `DetailedManga`), keyed by
    /// content hash. Lives above the parsers so the caching layer is shared.
    private var db: DatabasePool? {
        DbService.shared.openFsBrowsablePluginDb()
    }

    /// Directory holding the cached cover images and the cache database.
    private let cacheDir: URL = {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return (cachesDir ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent(CacheDirectory.index)
            .appendingPathComponent("fsbrowsableplugin")
    }()

    /// Prefix for cover references that point at a cached cover file in `cacheDir`
    /// rather than an entry inside an archive. Handled directly by `getImage`.
    private static let coverCachePrefix = "book-cover:"

    init(url: URL, id: String) {
        Logger.fsBrowsablePlugin.debug("Initializing FsBrowsablePlugin with url: \(url.path)")
        self.url = url
        _id = id

        let cbzParser = CbzParser(baseURL: url, pluginId: id)
        parsers = [
            cbzParser.id: cbzParser,
        ]

        super.init()

        if !(self is AppDirBrowsablePlugin) {
            _isAccessing = url.startAccessingSecurityScopedResource()
            if !_isAccessing {
                Logger.fsBrowsablePlugin.error(
                    "Failed to start accessing security scoped resource for plugin: \(_id)"
                )
            }
        }
    }

    convenience init(url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw NSError(
                domain: "FsBrowsablePlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "failedToAccessFolder")]
            )
        }
        defer {
            url.stopAccessingSecurityScopedResource()
        }

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }

        let idFile = url.appendingPathComponent(".mankai")
        let id: String

        if fileManager.fileExists(atPath: idFile.path) {
            id = try String(contentsOf: idFile, encoding: .utf8).trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        } else {
            id = UUID().uuidString
            try id.write(to: idFile, atomically: true, encoding: .utf8)
        }

        self.init(url: url, id: id)
    }

    deinit {
        if _isAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }

    static func loadPlugins() -> [FsBrowsablePlugin] {
        Logger.fsBrowsablePlugin.debug("Loading book plugins")
        guard let dbPool = DbService.shared.appDb else {
            Logger.fsBrowsablePlugin.error("Database not available")
            return []
        }

        var results: [FsBrowsablePlugin] = []

        var models: [FsBrowsablePluginModel] = []
        do {
            try dbPool.read { db in
                models = try FsBrowsablePluginModel.fetchAll(db)
            }
        } catch {
            Logger.fsBrowsablePlugin.error("Failed to fetch FsBrowsablePluginModels: \(error)")
            return []
        }

        for var model in models {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: model.bookmarkData,
                    options: .withoutUI,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                if isStale {
                    Logger.fsBrowsablePlugin.warning("Bookmark data is stale for plugin: \(model.id)")
                    do {
                        let newBookmarkData = try url.bookmarkData(
                            options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil
                        )
                        model.bookmarkData = newBookmarkData
                        try dbPool.write { db in
                            try model.update(db)
                        }
                        Logger.fsBrowsablePlugin.info("Updated stale bookmark for plugin: \(model.id)")
                    } catch {
                        Logger.fsBrowsablePlugin.error(
                            "Failed to update stale bookmark for plugin \(model.id): \(error)"
                        )
                        continue
                    }
                }

                if !url.startAccessingSecurityScopedResource() {
                    Logger.fsBrowsablePlugin.error(
                        "Failed to start accessing security scoped resource for plugin: \(model.id)"
                    )
                    continue
                }

                defer {
                    url.stopAccessingSecurityScopedResource()
                }

                let plugin = FsBrowsablePlugin(url: url, id: model.id)

                results.append(plugin)
            } catch {
                Logger.fsBrowsablePlugin.error("Failed to resolve bookmark for plugin \(model.id): \(error)")
            }
        }

        return results
    }

    override func savePlugin() throws {
        Logger.fsBrowsablePlugin.debug("Saving plugin: \(id)")
        guard let db = DbService.shared.appDb else {
            throw NSError(
                domain: "FsBrowsablePlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "databaseNotAvailable")]
            )
        }

        let bookmarkData = try url.bookmarkData(
            options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil
        )

        let pluginModel = FsBrowsablePluginModel(
            id: id,
            bookmarkData: bookmarkData
        )

        try db.write { db in
            try pluginModel.save(db)
        }
    }

    override func deletePlugin() throws {
        Logger.fsBrowsablePlugin.debug("Deleting plugin: \(id)")
        guard let db = DbService.shared.appDb else {
            throw NSError(
                domain: "FsBrowsablePlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "databaseNotAvailable")]
            )
        }

        _ = try db.write { db in
            try FsBrowsablePluginModel.deleteOne(db, key: id)
        }
    }

    // MARK: - Helper Methods

    private lazy var extensionsIndex: [String: Parser] = {
        var index: [String: Parser] = [:]
        for parser in parsers {
            for ext in parser.value.supportedExtensions {
                index[ext] = parser.value
            }
        }
        return index
    }()

    private func getParser(ext: String) -> Parser? {
        extensionsIndex[ext]
    }

    private func getParser(id: String) -> Parser? {
        parsers.first { $0.key == id }?.value
    }

    /// Splits a value prefixed with `<parserId>://` into the parser id and the
    /// remaining path. Used to route calls to the correct parser.
    private func parseMetaPrefix(_ value: String?) throws -> (parserId: String, path: String) {
        guard let value, let range = value.range(of: "://") else {
            Logger.fsBrowsablePlugin.error("Missing parser prefix in value: \(value ?? "nil")")
            throw NSError(
                domain: "FsBrowsablePlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "invalidMangaMeta")]
            )
        }

        let parserId = String(value[..<range.lowerBound])
        let path = String(value[range.upperBound...])
        // The path may legitimately be empty when the parser produced no
        // metadata of its own; only a missing parser id is invalid.
        guard !parserId.isEmpty else {
            Logger.fsBrowsablePlugin.error("Empty parser id in value: \(value)")
            throw NSError(
                domain: "FsBrowsablePlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "invalidMangaMeta")]
            )
        }

        return (parserId, path)
    }

    /// Prefixes the `id`, `meta`, and `cover` of a parser-returned manga with
    /// `<parserId>://` so that subsequent calls can route back to the parser
    /// that produced it. Works for both `Manga` and `DetailedManga`.
    ///
    /// Covers that already point at a FsBrowsablePlugin-managed cached file (`book-cover:`)
    /// are left untouched, since `getImage` resolves them directly.
    private func prefixManga<T: MangaMetaPrefixable>(_ manga: T, parserId: String) -> T {
        var prefixed = manga
        prefixed.meta = "\(parserId)://\(prefixed.meta ?? "")"
        if let cover = prefixed.cover, !cover.isEmpty, !cover.hasPrefix(Self.coverCachePrefix) {
            prefixed.cover = "\(parserId)://\(cover)"
        }
        prefixed.id = "\(parserId)://\(prefixed.id)"
        return prefixed
    }

    // MARK: - Plugin Methods

    /// SHOULD NOT BE CALLED
    override func getSuggestions(_ query: String) async throws -> [String] {
        Logger.fsBrowsablePlugin.debug("Getting suggestions for query: \(query)")
        fatalError("Not Implemented")
    }

    /// SHOULD NOT BE CALLED
    override func search(_ query: String, page: UInt) async throws -> [Manga] {
        Logger.fsBrowsablePlugin.debug("Searching for: \(query), page: \(page)")
        fatalError("Not Implemented")
    }

    /// SHOULD NOT BE CALLED
    override func getList(page: UInt, genre: Genre, status: Status) async throws -> [Manga] {
        Logger.fsBrowsablePlugin.debug("Getting list, page: \(page), genre: \(genre), status: \(status)")
        fatalError("Not Implemented")
    }

    override func getMangas(_ ids: [String]) async throws -> [Manga] {
        Logger.fsBrowsablePlugin.debug("Getting \(ids.count) mangas")

        var mangas: [Manga] = []
        for id in ids {
            do {
                let detailed = try await detailedManga(forPrefixedId: id)
                mangas.append(detailed.toManga())
            } catch {
                Logger.fsBrowsablePlugin.warning("Skipping manga \(id) in getMangas: \(error)")
            }
        }
        return mangas
    }

    override func getDetailedManga(_ id: String) async throws -> DetailedManga {
        Logger.fsBrowsablePlugin.debug("Getting detailed manga: \(id)")
        return try await detailedManga(forPrefixedId: id)
    }

    private func detailedManga(forPrefixedId id: String) async throws -> DetailedManga {
        let (parserId, originalId) = try parseMetaPrefix(id)
        guard getParser(id: parserId) != nil else {
            Logger.fsBrowsablePlugin.error("No parser found for id: \(parserId)")
            throw NSError(
                domain: "FsBrowsablePlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "parserNotFound")]
            )
        }

        guard let stored = try? await fetchCachedManga(mangaId: originalId, parserId: parserId) else {
            Logger.fsBrowsablePlugin.warning("Manga not found in cache: \(id)")
            throw NSError(
                domain: "FsBrowsablePlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "mangaNotFound")]
            )
        }

        var transformed = stored
        transformed.cover = await ensureCachedCover(
            for: stored.cover, mangaId: originalId, parserId: parserId
        )
        return prefixManga(transformed, parserId: parserId)
    }

    override func getChapter(manga: DetailedManga, chapter: Chapter) async throws -> [String] {
        Logger.fsBrowsablePlugin.debug("Getting chapter: \(chapter.id)")

        let (parserId, originalMeta) = try parseMetaPrefix(manga.meta)
        guard let parser = getParser(id: parserId) else {
            Logger.fsBrowsablePlugin.error("No parser found for id: \(parserId)")
            throw NSError(
                domain: "FsBrowsablePlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "parserNotFound")]
            )
        }

        var mangaForParser = manga
        mangaForParser.meta = originalMeta
        let (_, originalId) = try parseMetaPrefix(manga.id)
        mangaForParser.id = originalId
        let images = try await parser.parseChapter(manga: mangaForParser, chapter: chapter)

        // Prefix each returned image path with the parser id so that getImage can route to the correct parser.
        return images.map { "\(parserId)://\($0)" }
    }

    override func getImage(_ path: String) async throws -> Data {
        Logger.fsBrowsablePlugin.debug("Getting image: \(path)")

        if path.hasPrefix(Self.coverCachePrefix) {
            let filename = String(path.dropFirst(Self.coverCachePrefix.count))
            let coverURL = cacheDir.appendingPathComponent(filename)
            Logger.fsBrowsablePlugin.debug("Reading cached cover: \(coverURL.path(percentEncoded: false))")
            if let data = try? Data(contentsOf: coverURL) {
                return data
            }
            Logger.fsBrowsablePlugin.error("Cached cover not found on disk: \(filename)")
            throw NSError(
                domain: "FsBrowsablePlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "entryNotFound")]
            )
        }

        let (parserId, imagePath) = try parseMetaPrefix(path)
        guard let parser = getParser(id: parserId) else {
            Logger.fsBrowsablePlugin.error("No parser found for id: \(parserId)")
            throw NSError(
                domain: "FsBrowsablePlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "parserNotFound")]
            )
        }

        return try await parser.parseImage(path: imagePath)
    }

    override func isOnline() async throws -> Bool {
        return true
    }

    // MARK: - Caching

    private func parseAndCache(
        parser: Parser, relativePath: String, fullPath: String
    ) async throws -> DetailedManga {
        let hash = try Self.hashFile(at: fullPath)
        let mangaId = parser.getMangaId(path: relativePath, hash: hash)

        if let stored = try? await fetchCachedManga(mangaId: mangaId, parserId: parser.id) {
            // Refresh the stored path if the file moved but its content is unchanged.
            if stored.meta != relativePath {
                var updated = stored
                updated.cover = replaceCoverArchivePath(
                    updated.cover, from: stored.meta ?? "", to: relativePath
                )
                updated.meta = relativePath
                await storeManga(updated, mangaId: mangaId, parserId: parser.id)
                updated.cover = await ensureCachedCover(
                    for: updated.cover, mangaId: mangaId, parserId: parser.id
                )
                return updated
            }

            var cached = stored
            cached.cover = await ensureCachedCover(
                for: stored.cover, mangaId: mangaId, parserId: parser.id
            )
            return cached
        }

        var manga = try await parser.parse(path: relativePath, hash: mangaId)
        manga.meta = relativePath
        await storeManga(manga, mangaId: mangaId, parserId: parser.id)
        manga.cover = await ensureCachedCover(
            for: manga.cover, mangaId: mangaId, parserId: parser.id
        )

        return manga
    }

    private func fetchCachedManga(mangaId: String, parserId: String) async throws -> DetailedManga? {
        guard let db else { return nil }
        let pluginId = id
        let row = try await db.read { db in
            try FsBPMangaModel
                .filter(
                    Column("mangaId") == mangaId
                        && Column("parserId") == parserId
                        && Column("pluginId") == pluginId
                )
                .fetchOne(db)
        }
        guard let row,
              let data = row.info.data(using: .utf8),
              let stored = try? JSONDecoder().decode(DetailedManga.self, from: data)
        else { return nil }
        return stored
    }

    private func storeManga(_ manga: DetailedManga, mangaId: String, parserId: String) async {
        guard let db,
              let infoData = try? JSONEncoder().encode(manga),
              let infoString = String(data: infoData, encoding: .utf8)
        else { return }
        let model = FsBPMangaModel(
            mangaId: mangaId, parserId: parserId, pluginId: id, info: infoString
        )
        try? await db.write { db in
            try model.upsert(db)
        }
        Logger.fsBrowsablePlugin.debug("Stored parsed manga for \(mangaId) (parser: \(parserId))")
    }

    private func ensureCachedCover(
        for cover: String?, mangaId: String, parserId: String
    ) async -> String? {
        guard let cover, !cover.hasPrefix(Self.coverCachePrefix) else { return cover }

        let ext = (cover as NSString).pathExtension.lowercased()
        let filename = ext.isEmpty ? mangaId : "\(mangaId).\(ext)"
        let url = cacheDir.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            Logger.fsBrowsablePlugin.debug("Using cached cover for \(mangaId) at \(url.path(percentEncoded: false))")
            return "\(Self.coverCachePrefix)\(filename)"
        }

        guard let parser = getParser(id: parserId) else {
            Logger.fsBrowsablePlugin.warning("No parser \(parserId) to re-cache cover for \(mangaId)")
            return cover
        }

        do {
            let coverData = try await parser.parseImage(path: cover)
            try FileManager.default.createDirectory(
                at: cacheDir, withIntermediateDirectories: true, attributes: nil
            )
            try coverData.write(to: url, options: .atomic)
            Logger.fsBrowsablePlugin.debug(
                "Re-cached missing cover for \(mangaId) at \(url.path(percentEncoded: false))"
            )
            return "\(Self.coverCachePrefix)\(filename)"
        } catch {
            Logger.fsBrowsablePlugin.warning("Failed to re-cache cover for \(mangaId): \(error)")
            return cover
        }
    }

    private func replaceCoverArchivePath(
        _ cover: String?, from oldPath: String, to newPath: String
    ) -> String? {
        guard let cover, !cover.hasPrefix(Self.coverCachePrefix) else { return cover }
        let prefix = "\(oldPath):"
        guard cover.hasPrefix(prefix) else { return cover }
        let entryPath = String(cover.dropFirst(prefix.count))
        return "\(newPath):\(entryPath)"
    }

    private static func hashFile(at path: String) throws -> String {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw NSError(
                domain: "FsBrowsablePlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "unableToOpenFileForHashing")]
            )
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 1 << 16
        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Browsable Methods

    func getEntities(path: String? = "") async throws -> [EntityType] {
        Logger.fsBrowsablePlugin.debug("Getting entities for path: \(path ?? "root")")

        let target: URL
        if let path, !path.isEmpty {
            target = url.appendingPathComponent(path)
        } else {
            target = url
        }

        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]
        let entries = try fileManager.contentsOfDirectory(
            at: target,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        let basePath = url.standardizedFileURL.path
        var entities: [EntityType] = []

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try entry.resourceValues(forKeys: resourceKeys)

            // Compute a path that is relative to the plugin root.
            let runtimePath: String
            let standardized = entry.standardizedFileURL.path
            if standardized.hasPrefix(basePath) {
                let dropped = String(standardized.dropFirst(basePath.count))
                runtimePath = dropped.hasPrefix("/") ? String(dropped.dropFirst()) : dropped
            } else {
                runtimePath = entry.lastPathComponent
            }
            let fullPath = entry.standardizedFileURL.path

            if values.isDirectory == true {
                entities.append(.directory(path: runtimePath))
            } else if values.isRegularFile == true {
                let ext = entry.pathExtension.lowercased()
                guard let parser = getParser(ext: ext) else {
                    Logger.fsBrowsablePlugin.warning(
                        "No parser supports extension '\(ext)', skipping: \(runtimePath)"
                    )
                    continue
                }

                let detailed: DetailedManga
                do {
                    detailed = try await parseAndCache(
                        parser: parser, relativePath: runtimePath, fullPath: fullPath
                    )
                } catch {
                    Logger.fsBrowsablePlugin.warning(
                        "Parser '\(parser.id)' failed to parse '\(fullPath)': \(error), skipping"
                    )
                    continue
                }

                let prefixed = prefixManga(detailed, parserId: parser.id)
                entities.append(.book(manga: prefixed, path: runtimePath))
            }
        }

        return entities
    }

    func absoluteURL(for path: String?) -> URL? {
        if let path, !path.isEmpty {
            return url.appendingPathComponent(path)
        }
        return url
    }

    @discardableResult
    func importFile(from source: URL) throws -> URL {
        let fileManager = FileManager.default

        // Ensure the imports directory exists.
        if !fileManager.fileExists(atPath: importsDir.path) {
            try fileManager.createDirectory(
                at: importsDir, withIntermediateDirectories: true
            )
        }

        // Resolve a unique destination URL to avoid overwriting existing files.
        let baseName = source.lastPathComponent
        var destination = importsDir.appendingPathComponent(baseName)
        if fileManager.fileExists(atPath: destination.path) {
            let stem = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension
            var counter = 1
            repeat {
                let candidate = ext.isEmpty
                    ? "\(stem) (\(counter))"
                    : "\(stem) (\(counter)).\(ext)"
                destination = importsDir.appendingPathComponent(candidate)
                counter += 1
            } while fileManager.fileExists(atPath: destination.path)
        }

        // Access security-scoped resource if the source originates outside the app sandbox.
        let needsScopeAccess = source.startAccessingSecurityScopedResource()
        defer {
            if needsScopeAccess {
                source.stopAccessingSecurityScopedResource()
            }
        }

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            Logger.fsBrowsablePlugin.error("Failed to import file \(source.path): \(error)")
            throw error
        }

        Logger.fsBrowsablePlugin.info("Imported file to \(destination.path(percentEncoded: false))")
        return destination
    }
}

// MARK: - MangaMetaPrefixable

private protocol MangaMetaPrefixable {
    var id: String { get set }
    var meta: String? { get set }
    var cover: String? { get set }
}

extension Manga: MangaMetaPrefixable {}

extension DetailedManga: MangaMetaPrefixable {}
