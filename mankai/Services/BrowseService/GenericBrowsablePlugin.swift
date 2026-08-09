//
//  GenericBrowsablePlugin.swift
//  mankai
//
//  Created by Travis XU on 4/8/2026.
//

import CryptoKit
import Foundation
import GRDB
import SwiftUI

/// A backend-neutral entry returned by a browsable plugin.
struct BrowsableEntry {
    let path: String
    let isDirectory: Bool
    let isRegularFile: Bool

    var fileName: String {
        (path as NSString).lastPathComponent
    }
}

/// Common implementation for plugins that expose manga files through a
/// browsable hierarchy.
///
/// Subclasses provide the backend-specific operations through `entries(path:)`
/// and `parserFile(relativePath:cacheKey:)`.
class GenericBrowsablePlugin: Plugin, Browsable {
    override var id: String {
        _id
    }

    override var availableGenres: [Genre] {
        Genre.allCases
    }

    override var canDownload: Bool {
        false
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
        let index = Int(hash % UInt64(Self.systemImagePalette.count))
        return Self.systemImagePalette[index]
    }()

    var systemImageColor: Color {
        _systemImageColor
    }

    var supportedExtensions: [String] {
        extensionsIndex.keys.sorted()
    }

    var importsPath: String {
        "imports"
    }

    private let _id: String
    let parsers: [String: Parser]

    /// On-disk cache of route-neutral parsed manga (JSON-encoded
    /// `DetailedManga`), keyed by plugin, parser, and content hash. The
    /// relative path provides a secondary lookup that avoids hashing entries
    /// already seen while browsing.
    private var db: DatabasePool? {
        DbService.shared.openBrowsablePluginDb()
    }

    /// Root directory holding cached cover images and the cache database.
    /// The directory name is retained for compatibility with existing caches.
    private let cacheRootDir: URL = {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return (cachesDir ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent(CacheDirectory.index)
            .appendingPathComponent("browsableplugin")
    }()

    private var cacheDir: URL {
        cacheRootDir.appendingPathComponent(_id, isDirectory: true)
    }

    /// Prefix for cover references that point at a cached cover file rather
    /// than an entry inside the backend source.
    private static let coverCachePrefix = "book-cover:"

    init(id: String, parsers: [Parser]? = nil) {
        _id = id

        if let parsers {
            var parserIndex: [String: Parser] = [:]
            for parser in parsers {
                parserIndex[parser.id] = parser
            }
            self.parsers = parserIndex
        } else {
            let cbzParser = CbzParser()
            let cbrParser = CbrParser()
            let pdfParser = PdfParser()
            let epubParser = EpubParser()
            self.parsers = [
                cbzParser.id: cbzParser,
                cbrParser.id: cbrParser,
                pdfParser.id: pdfParser,
                epubParser.id: epubParser,
            ]
        }

        super.init()
    }

    // MARK: - Backend hooks

    /// Returns the entries directly below `path`. Returned paths must be
    /// relative to the plugin root and use `/` as their separator.
    func entries(path _: String?) async throws -> [BrowsableEntry] {
        fatalError("Not Implemented")
    }

    /// Creates a parser file for a backend entry. `cacheKey` identifies the
    /// current content and is used by parser-level caches.
    func parserFile(relativePath _: String, cacheKey _: String) async throws -> ParserFile {
        fatalError("Not Implemented")
    }

    /// Computes the content hash used in manga routes. The default reads the
    /// backend-neutral parser file, while backends that can stream data may
    /// override it.
    func hashFile(relativePath: String) async throws -> String {
        let file: ParserFile
        do {
            file = try await parserFile(relativePath: relativePath, cacheKey: "hash")
        } catch {
            throw MankaiErrorCode.browseFilesystemUnableToOpenFileForHashing.makeError(
                underlyingError: error
            )
        }

        do {
            let data = try await file.getContent()
            var hasher = SHA256()
            hasher.update(data: data)
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch {
            throw MankaiErrorCode.browseFilesystemUnableToOpenFileForHashing.makeError(
                underlyingError: error
            )
        }
    }

    /// Non-filesystem backends do not have a URL that can be opened in the
    /// Files app.
    func absoluteURL(for _: String?) -> URL? {
        nil
    }

    /// Importing is backend-specific. Filesystem-backed subclasses override
    /// this with a copy operation; network-backed subclasses can upload the
    /// source and upload it to their own destination if supported.
    func importFile(from _: URL) async throws {
        fatalError("Not Implemented")
    }

    // MARK: - Route helpers

    private lazy var extensionsIndex: [String: Parser] = {
        var index: [String: Parser] = [:]
        for parser in parsers.values {
            for ext in parser.supportedExtensions {
                index[ext] = parser
            }
        }
        return index
    }()

    func parser(forExtension ext: String) -> Parser? {
        extensionsIndex[ext]
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
                Logger.browseService.error("Unable to create manga route for: \(relativePath)")
                throw MankaiErrorCode.browseFilesystemInvalidMangaMeta.makeError()
            }

            self.parserId = parserId
            self.hash = hash
            self.relativePath = relativePath
        }

        init(mangaId: String) throws {
            guard let parserSeparator = mangaId.range(of: "://") else {
                Logger.browseService.error("Invalid manga route: \(mangaId)")
                throw MankaiErrorCode.browseFilesystemInvalidMangaMeta.makeError()
            }

            let parserId = String(mangaId[..<parserSeparator.lowerBound])
            let payload = mangaId[parserSeparator.upperBound...]
            guard let hashSeparator = payload.firstIndex(of: ":") else {
                Logger.browseService.error("Missing path in manga route: \(mangaId)")
                throw MankaiErrorCode.browseFilesystemInvalidMangaMeta.makeError()
            }

            let hash = String(payload[..<hashSeparator])
            let encodedRelativePath = String(payload[payload.index(after: hashSeparator)...])
            guard let relativePath = Self.decode(encodedRelativePath) else {
                Logger.browseService.error("Invalid encoded manga path: \(mangaId)")
                throw MankaiErrorCode.browseFilesystemInvalidMangaMeta.makeError()
            }

            try self.init(parserId: parserId, hash: hash, relativePath: relativePath)
        }

        func parser(in parsers: [String: Parser]) throws -> Parser {
            guard let parser = parsers[parserId] else {
                Logger.browseService.error("No parser found for id: \(parserId)")
                throw MankaiErrorCode.browseFilesystemParserNotFound.makeError()
            }
            return parser
        }

        func applying(_ manga: DetailedManga, coverCachePrefix: String) throws -> DetailedManga {
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
                Logger.browseService.error("Unable to encode parser image URL: \(parserURL)")
                throw MankaiErrorCode.browseFilesystemInvalidMangaMeta.makeError()
            }
            self.manga = manga
            self.parserURL = parserURL
        }

        init(imageId: String) throws {
            guard let separator = imageId.range(of: "#", options: .backwards),
                separator.upperBound < imageId.endIndex
            else {
                Logger.browseService.error("Invalid image route: \(imageId)")
                throw MankaiErrorCode.browseFilesystemInvalidMangaMeta.makeError()
            }

            let mangaId = String(imageId[..<separator.lowerBound])
            let encodedParserURL = String(imageId[separator.upperBound...])
            guard let parserURL = Self.decode(encodedParserURL) else {
                Logger.browseService.error("Invalid encoded parser image URL: \(imageId)")
                throw MankaiErrorCode.browseFilesystemInvalidMangaMeta.makeError()
            }

            try self.init(manga: MangaRoute(mangaId: mangaId), parserURL: parserURL)
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

    // MARK: - Plugin methods

    override func getMangas(_ ids: [String]) async throws -> [Manga] {
        Logger.browseService.debug("Getting \(ids.count) mangas")

        var mangas: [Manga] = []
        for id in ids {
            do {
                try mangas.append(await detailedManga(forPrefixedId: id).toManga())
            } catch {
                Logger.browseService.warning("Skipping manga \(id) in getMangas: \(error)")
            }
        }
        return mangas
    }

    override func getDetailedManga(_ id: String) async throws -> DetailedManga {
        Logger.browseService.debug("Getting detailed manga: \(id)")
        return try await detailedManga(forPrefixedId: id)
    }

    func parseFile(path: String, fileType: String) async throws -> DetailedManga {
        let normalizedFileType =
            fileType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let parser = parser(forExtension: normalizedFileType) else {
            Logger.browseService.error(
                "No parser found for file type '\(fileType)' at path: \(path)"
            )
            throw MankaiErrorCode.browseFilesystemParserNotFound.makeError()
        }

        Logger.browseService.debug(
            "Parsing browsable file '\(path)' as '\(normalizedFileType)'"
        )
        do {
            return try await parseAndCache(parser: parser, relativePath: path)
        } catch {
            Logger.browseService.warning(
                "Parser '\(parser.id)' failed to parse '\(path)': \(error)"
            )
            throw error
        }
    }

    private func detailedManga(forPrefixedId id: String) async throws -> DetailedManga {
        try await loadManga(route: MangaRoute(mangaId: id))
    }

    private func parserFile(for route: MangaRoute) async throws -> ParserFile {
        try await parserFile(relativePath: route.relativePath, cacheKey: route.hash)
    }

    private func loadManga(route: MangaRoute) async throws -> DetailedManga {
        let parser = try route.parser(in: parsers)
        let file = try await parserFile(for: route)

        let stored: DetailedManga
        if let cached = try? await fetchCachedManga(mangaId: route.hash, parserId: route.parserId) {
            Logger.browseService.debug("Manga cache hit: \(route.relativePath)")
            stored = cached.manga
            if cached.path != route.relativePath {
                await storeManga(
                    cached.manga,
                    mangaId: route.hash,
                    parserId: route.parserId,
                    path: route.relativePath
                )
            }
        } else {
            Logger.browseService.debug("Manga cache miss, parsing source: \(route.relativePath)")
            var parsed = try await parser.parse(file: file)
            parsed.id = route.hash
            await storeManga(
                parsed,
                mangaId: route.hash,
                parserId: route.parserId,
                path: route.relativePath
            )
            stored = parsed
        }

        return try await prepareCachedManga(stored, route: route, parser: parser, file: file)
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
        return try route.applying(transformed, coverCachePrefix: Self.coverCachePrefix)
    }

    override func getChapter(manga: DetailedManga, chapter: Chapter) async throws -> [String] {
        Logger.browseService.debug("Getting chapter: \(chapter.id)")
        let route = try MangaRoute(mangaId: manga.id)
        let parser = try route.parser(in: parsers)
        let file = try await parserFile(for: route)
        let images = try await parser.parseChapter(manga: manga, chapter: chapter, file: file)
        return try images.map { try ImageRoute(manga: route, parserURL: $0).imageId }
    }

    override func getImage(_ path: String) async throws -> Data {
        Logger.browseService.debug("Getting image: \(path)")

        if path.hasPrefix(Self.coverCachePrefix) {
            let filename = String(path.dropFirst(Self.coverCachePrefix.count))
            let coverURL = cacheDir.appendingPathComponent(filename)
            if let data = try? Data(contentsOf: coverURL) {
                return data
            }
            throw MankaiErrorCode.browseFilesystemEntryNotFound.makeError()
        }

        let imageRoute = try ImageRoute(imageId: path)
        let parser = try imageRoute.parser(in: parsers)
        let file = try await parserFile(for: imageRoute.manga)
        return try await parser.parseImage(url: imageRoute.parserURL, file: file)
    }

    override func isOnline() async throws -> Bool {
        true
    }

    // MARK: - Caching

    private struct CachedManga {
        let mangaId: String
        let path: String
        let manga: DetailedManga
    }

    private func parseAndCache(parser: Parser, relativePath: String) async throws -> DetailedManga {
        if let cached = try? await fetchCachedManga(path: relativePath, parserId: parser.id) {
            Logger.browseService.debug("Browsable source cache hit: \(relativePath)")
            let route = try MangaRoute(
                parserId: parser.id,
                hash: cached.mangaId,
                relativePath: relativePath
            )
            let file = try await parserFile(for: route)
            return try await prepareCachedManga(
                cached.manga, route: route, parser: parser, file: file)
        }

        Logger.browseService.debug("Browsable source cache miss, hashing: \(relativePath)")
        let hash = try await hashFile(relativePath: relativePath)
        let route = try MangaRoute(parserId: parser.id, hash: hash, relativePath: relativePath)
        return try await loadManga(route: route)
    }

    private func fetchCachedManga(mangaId: String, parserId: String) async throws -> CachedManga? {
        guard let db else { return nil }
        let row = try await db.read { db in
            try BrowsablePluginMangaModel
                .filter(
                    Column("mangaId") == mangaId
                        && Column("parserId") == parserId
                        && Column("pluginId") == id
                )
                .fetchOne(db)
        }
        return Self.decodeCachedManga(row)
    }

    private func fetchCachedManga(path: String, parserId: String) async throws -> CachedManga? {
        guard let db else { return nil }
        let row = try await db.read { db in
            try BrowsablePluginMangaModel
                .filter(
                    Column("path") == path
                        && Column("parserId") == parserId
                        && Column("pluginId") == id
                )
                .fetchOne(db)
        }
        return Self.decodeCachedManga(row)
    }

    private static func decodeCachedManga(_ row: BrowsablePluginMangaModel?) -> CachedManga? {
        guard let row,
            let data = row.info.data(using: .utf8),
            let stored = try? JSONDecoder().decode(DetailedManga.self, from: data)
        else { return nil }
        return CachedManga(mangaId: row.mangaId, path: row.path, manga: stored)
    }

    private func storeManga(
        _ manga: DetailedManga,
        mangaId: String,
        parserId: String,
        path: String
    ) async {
        guard let db,
            let infoData = try? JSONEncoder().encode(manga),
            let infoString = String(data: infoData, encoding: .utf8)
        else { return }

        let model = BrowsablePluginMangaModel(
            mangaId: mangaId,
            parserId: parserId,
            pluginId: id,
            path: path,
            info: infoString
        )
        try? await db.write { db in
            try model.upsert(db)
        }
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
        let coverURL = cacheDir.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: coverURL.path(percentEncoded: false)) {
            return "\(Self.coverCachePrefix)\(filename)"
        }

        do {
            let coverData = try await parser.parseImage(url: cover, file: file)
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try coverData.write(to: coverURL, options: .atomic)
            return "\(Self.coverCachePrefix)\(filename)"
        } catch {
            Logger.browseService.warning("Failed to cache cover for \(route.mangaId): \(error)")
            return cover
        }
    }

    /// Clears parser metadata and locally cached covers for this plugin.
    func clearCache() throws {
        if let db {
            _ = try db.write { db in
                try BrowsablePluginMangaModel
                    .filter(Column("pluginId") == id)
                    .deleteAll(db)
            }
        }

        if FileManager.default.fileExists(atPath: cacheDir.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: cacheDir)
        }
    }

    override func deletePlugin() throws {
        try clearCache()
    }

    // MARK: - Browsable methods

    func getEntities(path: String? = "") async throws -> [EntityType] {
        Logger.browseService.debug("Getting entities for path: \(path ?? "root")")
        let entries = try await entries(path: path)
        var entities: [EntityType] = []

        for entry in entries.sorted(by: { $0.fileName < $1.fileName }) {
            if entry.isDirectory {
                entities.append(.directory(path: entry.path))
                continue
            }
            guard entry.isRegularFile else { continue }

            let ext = (entry.path as NSString).pathExtension.lowercased()
            guard parser(forExtension: ext) != nil else { continue }

            entities.append(.book(path: entry.path, fileType: ext))
        }

        return entities
    }
}
