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

    /// On-disk cache of route-neutral parsed manga (JSON-encoded `DetailedManga`),
    /// keyed by parser and content hash. A cheap file-system fingerprint provides
    /// a best-effort lookup that avoids hashing unchanged files during browsing.
    private var db: DatabasePool? {
        DbService.shared.openFsBrowsablePluginDb()
    }

    /// Root directory holding the cached cover images and the cache database.
    private let cacheRootDir: URL = {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return (cachesDir ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent(CacheDirectory.index)
            .appendingPathComponent("fsbrowsableplugin")
    }()

    /// Directory holding this plugin's cached cover images.
    private var cacheDir: URL {
        cacheRootDir.appendingPathComponent(_id, isDirectory: true)
    }

    /// Prefix for cover references that point at a cached cover file in `cacheDir`
    /// rather than an entry inside an archive. Handled directly by `getImage`.
    private static let coverCachePrefix = "book-cover:"

    init(url: URL, id: String) {
        Logger.fsBrowsablePlugin.debug("Initializing FsBrowsablePlugin with url: \(url.path)")
        self.url = url
        _id = id

        let cbzParser = CbzParser()
        let cbrParser = CbrParser()
        let pdfParser = PdfParser()
        let epubParser = EpubParser()
        parsers = [
            cbzParser.id: cbzParser,
            cbrParser.id: cbrParser,
            pdfParser.id: pdfParser,
            epubParser.id: epubParser,
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
            throw MankaiErrorCode.browseFilesystemFailedToAccessFolder.makeError()
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
            throw MankaiErrorCode.browseFilesystemDatabaseNotAvailable.makeError()
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
            throw MankaiErrorCode.browseFilesystemDatabaseNotAvailable.makeError()
        }

        _ = try db.write { db in
            try FsBrowsablePluginModel.deleteOne(db, key: id)
        }

        try clearCache()
    }

    private func clearCache() throws {
        if let db = DbService.shared.openFsBrowsablePluginDb() {
            _ = try db.write { db in
                try FsBPMangaModel
                    .filter(Column("pluginId") == id)
                    .deleteAll(db)
            }
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: cacheDir.path(percentEncoded: false)) {
            try fileManager.removeItem(at: cacheDir)
        }

        Logger.fsBrowsablePlugin.info("Cleared cache for plugin: \(id)")
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

    private func parserFile(for route: MangaRoute, sourceURL: URL) -> ParserFile {
        FsParserFile(
            cacheKey: route.hash,
            url: sourceURL
        )
    }

    private struct MangaRoute {
        let parserId: String
        let hash: String
        let relativePath: String

        var mangaId: String {
            "\(parserId)://\(hash):\(Self.encode(relativePath)!)"
        }

        init(parserId: String, hash: String, relativePath: String) throws {
            let isSHA256 = hash.count == 64 && hash.allSatisfy(\.isHexDigit)
            guard !parserId.isEmpty,
                  isSHA256,
                  !relativePath.isEmpty,
                  Self.encode(relativePath) != nil
            else {
                Logger.fsBrowsablePlugin.error(
                    "Unable to create manga route for: \(relativePath)"
                )
                throw MankaiErrorCode.browseFilesystemInvalidMangaMeta.makeError()
            }

            self.parserId = parserId
            self.hash = hash
            self.relativePath = relativePath
        }

        init(mangaId: String) throws {
            guard let parserSeparator = mangaId.range(of: "://") else {
                Logger.fsBrowsablePlugin.error("Invalid manga route: \(mangaId)")
                throw MankaiErrorCode.browseFilesystemInvalidMangaMeta.makeError()
            }

            let parserId = String(mangaId[..<parserSeparator.lowerBound])
            let payload = mangaId[parserSeparator.upperBound...]
            guard let hashSeparator = payload.firstIndex(of: ":") else {
                Logger.fsBrowsablePlugin.error("Missing path in manga route: \(mangaId)")
                throw MankaiErrorCode.browseFilesystemInvalidMangaMeta.makeError()
            }

            let hash = String(payload[..<hashSeparator])
            let encodedRelativePath = String(payload[payload.index(after: hashSeparator)...])
            guard let relativePath = Self.decode(encodedRelativePath) else {
                Logger.fsBrowsablePlugin.error("Invalid encoded manga path: \(mangaId)")
                throw MankaiErrorCode.browseFilesystemInvalidMangaMeta.makeError()
            }

            try self.init(
                parserId: parserId,
                hash: hash,
                relativePath: relativePath
            )
        }

        func sourceURL(relativeTo rootURL: URL) throws -> URL {
            try Self.sourceURL(for: relativePath, relativeTo: rootURL)
        }

        static func sourceURL(
            for relativePath: String, relativeTo rootURL: URL
        ) throws -> URL {
            let rootURL = rootURL.standardizedFileURL
            let sourceURL = rootURL.appendingPathComponent(relativePath).standardizedFileURL
            let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : "\(rootURL.path)/"
            guard sourceURL.path.hasPrefix(rootPath) else {
                Logger.fsBrowsablePlugin.error(
                    "Manga route escapes plugin root: \(relativePath)"
                )
                throw MankaiErrorCode.browseFilesystemInvalidMangaMeta.makeError()
            }
            return sourceURL
        }

        func parser(in parsers: [String: Parser]) throws -> Parser {
            guard let parser = parsers[parserId] else {
                Logger.fsBrowsablePlugin.error("No parser found for id: \(parserId)")
                throw MankaiErrorCode.browseFilesystemParserNotFound.makeError()
            }
            return parser
        }

        func applying(
            to manga: DetailedManga, coverCachePrefix: String
        ) throws -> DetailedManga {
            var routed = manga
            routed.id = mangaId
            if let cover = routed.cover,
               !cover.isEmpty,
               !cover.hasPrefix(coverCachePrefix)
            {
                routed.cover = try ImageRoute(manga: self, parserURL: cover).imageId
            }
            return routed
        }

        private static let allowedCharacters: CharacterSet = {
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~/")
            return allowed
        }()

        private static func encode(_ relativePath: String) -> String? {
            relativePath.addingPercentEncoding(withAllowedCharacters: allowedCharacters)
        }

        private static func decode(_ relativePath: String) -> String? {
            relativePath.removingPercentEncoding
        }
    }

    private struct ImageRoute {
        let manga: MangaRoute
        let parserURL: String

        var imageId: String {
            "\(manga.mangaId)#\(Self.encode(parserURL)!)"
        }

        init(manga: MangaRoute, parserURL: String) throws {
            guard !parserURL.isEmpty, Self.encode(parserURL) != nil else {
                Logger.fsBrowsablePlugin.error(
                    "Unable to encode parser image URL: \(parserURL)"
                )
                throw MankaiErrorCode.browseFilesystemInvalidMangaMeta.makeError()
            }
            self.manga = manga
            self.parserURL = parserURL
        }

        init(imageId: String) throws {
            guard let separator = imageId.range(of: "#", options: .backwards),
                  separator.upperBound < imageId.endIndex
            else {
                Logger.fsBrowsablePlugin.error("Invalid image route: \(imageId)")
                throw MankaiErrorCode.browseFilesystemInvalidMangaMeta.makeError()
            }

            let mangaId = String(imageId[..<separator.lowerBound])
            let encodedParserURL = String(imageId[separator.upperBound...])
            guard let parserURL = Self.decode(encodedParserURL) else {
                Logger.fsBrowsablePlugin.error(
                    "Invalid encoded parser image URL: \(imageId)"
                )
                throw MankaiErrorCode.browseFilesystemInvalidMangaMeta.makeError()
            }

            try self.init(
                manga: MangaRoute(mangaId: mangaId),
                parserURL: parserURL
            )
        }

        func sourceURL(relativeTo rootURL: URL) throws -> URL {
            try manga.sourceURL(relativeTo: rootURL)
        }

        func parser(in parsers: [String: Parser]) throws -> Parser {
            try manga.parser(in: parsers)
        }

        private static let allowedCharacters: CharacterSet = {
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~/")
            return allowed
        }()

        private static func encode(_ parserURL: String) -> String? {
            parserURL.addingPercentEncoding(withAllowedCharacters: allowedCharacters)
        }

        private static func decode(_ parserURL: String) -> String? {
            parserURL.removingPercentEncoding
        }
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
        let route = try MangaRoute(mangaId: id)
        return try await loadManga(route: route)
    }

    private func loadManga(
        route: MangaRoute,
        cacheKey: String? = nil
    ) async throws -> DetailedManga {
        let parser = try route.parser(in: parsers)
        let sourceURL = try route.sourceURL(relativeTo: url)
        let file = parserFile(for: route, sourceURL: sourceURL)

        let stored: DetailedManga
        if let cached = try? await fetchCachedManga(
            mangaId: route.hash, parserId: route.parserId
        ) {
            stored = cached.manga
            if let cacheKey, cached.cacheKey != cacheKey {
                await storeManga(
                    cached.manga,
                    mangaId: route.hash,
                    parserId: route.parserId,
                    cacheKey: cacheKey
                )
            }
        } else {
            Logger.fsBrowsablePlugin.debug("Manga cache miss, parsing source: \(sourceURL.path)")

            var parsed = try await parser.parse(file: file)
            parsed.id = route.hash
            await storeManga(
                parsed,
                mangaId: route.hash,
                parserId: route.parserId,
                cacheKey: cacheKey ?? "hash:\(route.hash)"
            )
            stored = parsed
        }

        return try await prepareCachedManga(
            stored,
            route: route,
            parser: parser,
            file: file
        )
    }

    private func prepareCachedManga(
        _ stored: DetailedManga,
        route: MangaRoute,
        parser: Parser,
        file: ParserFile
    ) async throws -> DetailedManga {
        var transformed = parser.prepareForPresentation(stored, file: file)
        transformed.cover = await ensureCachedCover(
            for: transformed.cover,
            route: route,
            parser: parser,
            file: file
        )
        return try route.applying(
            to: transformed,
            coverCachePrefix: Self.coverCachePrefix
        )
    }

    override func getChapter(manga: DetailedManga, chapter: Chapter) async throws -> [String] {
        Logger.fsBrowsablePlugin.debug("Getting chapter: \(chapter.id)")

        let route = try MangaRoute(mangaId: manga.id)
        let parser = try route.parser(in: parsers)
        let sourceURL = try route.sourceURL(relativeTo: url)
        let file = parserFile(for: route, sourceURL: sourceURL)
        let images = try await parser.parseChapter(
            manga: manga, chapter: chapter, file: file
        )

        return try images.map {
            try ImageRoute(manga: route, parserURL: $0).imageId
        }
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
            throw MankaiErrorCode.browseFilesystemEntryNotFound.makeError()
        }

        let imageRoute = try ImageRoute(imageId: path)
        let parser = try imageRoute.parser(in: parsers)
        let sourceURL = try imageRoute.sourceURL(relativeTo: url)
        let file = parserFile(for: imageRoute.manga, sourceURL: sourceURL)
        return try await parser.parseImage(url: imageRoute.parserURL, file: file)
    }

    override func isOnline() async throws -> Bool {
        return true
    }

    // MARK: - Caching

    private func parseAndCache(
        parser: Parser,
        relativePath: String,
        resourceValues: URLResourceValues
    ) async throws -> DetailedManga {
        let sourceURL = try MangaRoute.sourceURL(
            for: relativePath,
            relativeTo: url
        )
        let cacheKey = Self.cacheKey(for: resourceValues)

        if let cacheKey,
           let cached = try? await fetchCachedManga(
               cacheKey: cacheKey,
               parserId: parser.id
           )
        {
            Logger.fsBrowsablePlugin.debug(
                "Manga cache hit for filesystem key: \(cacheKey)"
            )
            let route = try MangaRoute(
                parserId: parser.id,
                hash: cached.mangaId,
                relativePath: relativePath
            )
            let file = parserFile(for: route, sourceURL: sourceURL)
            return try await prepareCachedManga(
                cached.manga,
                route: route,
                parser: parser,
                file: file
            )
        }

        Logger.fsBrowsablePlugin.debug(
            "Filesystem cache miss, hashing source: \(sourceURL.path)"
        )
        let hash = try Self.hashFile(at: sourceURL)
        let route = try MangaRoute(
            parserId: parser.id,
            hash: hash,
            relativePath: relativePath
        )

        return try await loadManga(route: route, cacheKey: cacheKey)
    }

    private struct CachedManga {
        let mangaId: String
        let cacheKey: String
        let manga: DetailedManga
    }

    private func fetchCachedManga(
        mangaId: String,
        parserId: String
    ) async throws -> CachedManga? {
        guard let db else { return nil }
        let row = try await db.read { db in
            try FsBPMangaModel
                .filter(
                    Column("mangaId") == mangaId
                        && Column("parserId") == parserId
                        && Column("pluginId") == id
                )
                .fetchOne(db)
        }
        return Self.decodeCachedManga(row)
    }

    private func fetchCachedManga(
        cacheKey: String,
        parserId: String
    ) async throws -> CachedManga? {
        guard let db else { return nil }
        let row = try await db.read { db in
            try FsBPMangaModel
                .filter(
                    Column("cacheKey") == cacheKey
                        && Column("parserId") == parserId
                        && Column("pluginId") == id
                )
                .fetchOne(db)
        }
        return Self.decodeCachedManga(row)
    }

    private static func decodeCachedManga(_ row: FsBPMangaModel?) -> CachedManga? {
        guard let row,
              let data = row.info.data(using: .utf8),
              let stored = try? JSONDecoder().decode(DetailedManga.self, from: data)
        else { return nil }
        return CachedManga(
            mangaId: row.mangaId,
            cacheKey: row.cacheKey,
            manga: stored
        )
    }

    private func storeManga(
        _ manga: DetailedManga,
        mangaId: String,
        parserId: String,
        cacheKey: String
    ) async {
        guard let db,
              let infoData = try? JSONEncoder().encode(manga),
              let infoString = String(data: infoData, encoding: .utf8)
        else { return }
        let model = FsBPMangaModel(
            mangaId: mangaId,
            parserId: parserId,
            pluginId: id,
            cacheKey: cacheKey,
            info: infoString
        )
        try? await db.write { db in
            try model.upsert(db)
        }
        Logger.fsBrowsablePlugin.debug("Stored parsed manga for \(mangaId) (parser: \(parserId))")
    }

    private func ensureCachedCover(
        for cover: String?,
        route: MangaRoute,
        parser: Parser,
        file: ParserFile
    ) async -> String? {
        guard let cover, !cover.hasPrefix(Self.coverCachePrefix) else { return cover }

        let ext = (cover as NSString).pathExtension.lowercased()
        let filename = ext.isEmpty ? route.hash : "\(route.hash).\(ext)"
        let url = cacheDir.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            Logger.fsBrowsablePlugin.debug(
                "Using cached cover for \(route.mangaId) at \(url.path(percentEncoded: false))"
            )
            return "\(Self.coverCachePrefix)\(filename)"
        }

        do {
            let coverData = try await parser.parseImage(url: cover, file: file)
            try FileManager.default.createDirectory(
                at: cacheDir, withIntermediateDirectories: true, attributes: nil
            )
            try coverData.write(to: url, options: .atomic)
            Logger.fsBrowsablePlugin.debug(
                "Re-cached missing cover for \(route.mangaId) at \(url.path(percentEncoded: false))"
            )
            return "\(Self.coverCachePrefix)\(filename)"
        } catch {
            Logger.fsBrowsablePlugin.warning(
                "Failed to re-cache cover for \(route.mangaId): \(error)"
            )
            return cover
        }
    }

    private static func hashFile(at url: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw MankaiErrorCode.browseFilesystemUnableToOpenFileForHashing.makeError()
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

    private static func cacheKey(for values: URLResourceValues) -> String? {
        let volumeIdentifier = encodedResourceIdentifier(values.volumeIdentifier) ?? "-"
        let generationIdentifier = encodedResourceIdentifier(values.generationIdentifier)

        if let fileContentIdentifier = values.fileContentIdentifier {
            var components = [
                "content",
                volumeIdentifier,
                String(fileContentIdentifier),
            ]
            if let generationIdentifier {
                components.append(generationIdentifier)
            }
            return components.joined(separator: ":")
        }

        if let generationIdentifier {
            return [
                "generation",
                volumeIdentifier,
                generationIdentifier,
            ].joined(separator: ":")
        }

        if let fileSize = values.fileSize,
           let contentModificationDate = values.contentModificationDate
        {
            return [
                "metadata",
                volumeIdentifier,
                String(fileSize),
                String(
                    contentModificationDate.timeIntervalSinceReferenceDate.bitPattern,
                    radix: 16
                ),
            ].joined(separator: ":")
        }

        return nil
    }

    private static func encodedResourceIdentifier(
        _ identifier: (any NSCopying & NSSecureCoding & NSObjectProtocol)?
    ) -> String? {
        guard let identifier else { return nil }

        if let data = identifier as? Data {
            return data.base64EncodedString()
        }
        if let number = identifier as? NSNumber {
            return number.stringValue
        }
        if let string = identifier as? NSString {
            return string as String
        }
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: identifier,
            requiringSecureCoding: true
        ) else {
            return nil
        }
        return data.base64EncodedString()
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
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .volumeIdentifierKey,
            .fileContentIdentifierKey,
            .generationIdentifierKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]
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
                        parser: parser,
                        relativePath: runtimePath,
                        resourceValues: values
                    )
                } catch {
                    Logger.fsBrowsablePlugin.warning(
                        "Parser '\(parser.id)' failed to parse '\(entry.path)': \(error), skipping"
                    )
                    continue
                }

                entities.append(.book(manga: detailed, path: runtimePath))
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
