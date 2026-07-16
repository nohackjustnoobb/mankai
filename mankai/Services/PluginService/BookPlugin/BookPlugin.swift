//
//  BookPlugin.swift
//  mankai
//
//  Created by Travis XU on 13/7/2026.
//

import Foundation
import GRDB
import SwiftUI

class BookPlugin: Plugin, Browsable {
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
        let index = Int(hash % UInt64(BookPlugin.systemImagePalette.count))
        return BookPlugin.systemImagePalette[index]
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

    init(url: URL, id: String) {
        Logger.bookPlugin.debug("Initializing BookPlugin with url: \(url.path)")
        self.url = url
        _id = id

        let cbzParser = CbzParser(baseURL: url, pluginId: id)
        parsers = [
            cbzParser.id: cbzParser,
        ]

        super.init()

        if !(self is AppDirBookPlugin) {
            _isAccessing = url.startAccessingSecurityScopedResource()
            if !_isAccessing {
                Logger.bookPlugin.error(
                    "Failed to start accessing security scoped resource for plugin: \(_id)"
                )
            }
        }
    }

    convenience init(url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw NSError(
                domain: "BookPlugin", code: 0,
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

    static func loadPlugins() -> [BookPlugin] {
        Logger.bookPlugin.debug("Loading book plugins")
        guard let dbPool = DbService.shared.appDb else {
            Logger.bookPlugin.error("Database not available")
            return []
        }

        var results: [BookPlugin] = []

        var models: [BookPluginModel] = []
        do {
            try dbPool.read { db in
                models = try BookPluginModel.fetchAll(db)
            }
        } catch {
            Logger.bookPlugin.error("Failed to fetch BookPluginModels: \(error)")
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
                    Logger.bookPlugin.warning("Bookmark data is stale for plugin: \(model.id)")
                    do {
                        let newBookmarkData = try url.bookmarkData(
                            options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil
                        )
                        model.bookmarkData = newBookmarkData
                        try dbPool.write { db in
                            try model.update(db)
                        }
                        Logger.bookPlugin.info("Updated stale bookmark for plugin: \(model.id)")
                    } catch {
                        Logger.bookPlugin.error(
                            "Failed to update stale bookmark for plugin \(model.id): \(error)"
                        )
                        continue
                    }
                }

                if !url.startAccessingSecurityScopedResource() {
                    Logger.bookPlugin.error(
                        "Failed to start accessing security scoped resource for plugin: \(model.id)"
                    )
                    continue
                }

                defer {
                    url.stopAccessingSecurityScopedResource()
                }

                let plugin = BookPlugin(url: url, id: model.id)

                results.append(plugin)
            } catch {
                Logger.bookPlugin.error("Failed to resolve bookmark for plugin \(model.id): \(error)")
            }
        }

        return results
    }

    override func savePlugin() throws {
        Logger.bookPlugin.debug("Saving plugin: \(id)")
        guard let db = DbService.shared.appDb else {
            throw NSError(
                domain: "BookPlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "databaseNotAvailable")]
            )
        }

        let bookmarkData = try url.bookmarkData(
            options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil
        )

        let pluginModel = BookPluginModel(
            id: id,
            bookmarkData: bookmarkData
        )

        try db.write { db in
            try pluginModel.save(db)
        }
    }

    override func deletePlugin() throws {
        Logger.bookPlugin.debug("Deleting plugin: \(id)")
        guard let db = DbService.shared.appDb else {
            throw NSError(
                domain: "BookPlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "databaseNotAvailable")]
            )
        }

        _ = try db.write { db in
            try BookPluginModel.deleteOne(db, key: id)
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
            Logger.bookPlugin.error("Missing parser prefix in value: \(value ?? "nil")")
            throw NSError(
                domain: "BookPlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "invalidMangaMeta")]
            )
        }

        let parserId = String(value[..<range.lowerBound])
        let path = String(value[range.upperBound...])
        // The path may legitimately be empty when the parser produced no
        // metadata of its own; only a missing parser id is invalid.
        guard !parserId.isEmpty else {
            Logger.bookPlugin.error("Empty parser id in value: \(value)")
            throw NSError(
                domain: "BookPlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "invalidMangaMeta")]
            )
        }

        return (parserId, path)
    }

    /// Prefixes the `id`, `meta`, and `cover` of a parser-returned manga with
    /// `<parserId>://` so that subsequent calls can route back to the parser
    /// that produced it. Works for both `Manga` and `DetailedManga`.
    private func prefixManga<T: MangaMetaPrefixable>(_ manga: T, parserId: String) -> T {
        var prefixed = manga
        prefixed.meta = "\(parserId)://\(prefixed.meta ?? "")"
        if let cover = prefixed.cover, !cover.isEmpty {
            prefixed.cover = "\(parserId)://\(cover)"
        }
        prefixed.id = "\(parserId)://\(prefixed.id)"
        return prefixed
    }

    // MARK: - Plugin Methods

    /// SHOULD NOT BE CALLED
    override func getSuggestions(_ query: String) async throws -> [String] {
        Logger.bookPlugin.debug("Getting suggestions for query: \(query)")
        fatalError("Not Implemented")
    }

    /// SHOULD NOT BE CALLED
    override func search(_ query: String, page: UInt) async throws -> [Manga] {
        Logger.bookPlugin.debug("Searching for: \(query), page: \(page)")
        fatalError("Not Implemented")
    }

    /// SHOULD NOT BE CALLED
    override func getList(page: UInt, genre: Genre, status: Status) async throws -> [Manga] {
        Logger.bookPlugin.debug("Getting list, page: \(page), genre: \(genre), status: \(status)")
        fatalError("Not Implemented")
    }

    override func getMangas(_ ids: [String]) async throws -> [Manga] {
        Logger.bookPlugin.debug("Getting \(ids.count) mangas")

        var mangas: [Manga] = []
        for id in ids {
            let (parserId, originalId) = try parseMetaPrefix(id)
            guard let parser = getParser(id: parserId) else {
                Logger.bookPlugin.error("No parser found for id: \(parserId)")
                throw NSError(
                    domain: "BookPlugin", code: 0,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "parserNotFound")]
                )
            }

            let parsed = try await parser.getMangas([originalId])
            mangas.append(contentsOf: parsed.map { prefixManga($0, parserId: parserId) })
        }
        return mangas
    }

    override func getDetailedManga(_ id: String) async throws -> DetailedManga {
        Logger.bookPlugin.debug("Getting detailed manga: \(id)")

        let (parserId, originalId) = try parseMetaPrefix(id)
        guard let parser = getParser(id: parserId) else {
            Logger.bookPlugin.error("No parser found for id: \(parserId)")
            throw NSError(
                domain: "BookPlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "parserNotFound")]
            )
        }

        let detailed = try await parser.getDetailedManga(originalId)
        return prefixManga(detailed, parserId: parserId)
    }

    override func getChapter(manga: DetailedManga, chapter: Chapter) async throws -> [String] {
        Logger.bookPlugin.debug("Getting chapter: \(chapter.id)")

        let (parserId, originalMeta) = try parseMetaPrefix(manga.meta)
        guard let parser = getParser(id: parserId) else {
            Logger.bookPlugin.error("No parser found for id: \(parserId)")
            throw NSError(
                domain: "BookPlugin", code: 0,
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
        Logger.bookPlugin.debug("Getting image: \(path)")

        let (parserId, imagePath) = try parseMetaPrefix(path)
        guard let parser = getParser(id: parserId) else {
            Logger.bookPlugin.error("No parser found for id: \(parserId)")
            throw NSError(
                domain: "BookPlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "parserNotFound")]
            )
        }

        return try await parser.parseImage(path: imagePath)
    }

    override func isOnline() async throws -> Bool {
        return true
    }

    // MARK: - Browsable Methods

    func getEntities(path: String? = "") async throws -> [EntityType] {
        Logger.bookPlugin.debug("Getting entities for path: \(path ?? "root")")

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
                    Logger.bookPlugin.warning(
                        "No parser supports extension '\(ext)', skipping: \(runtimePath)"
                    )
                    continue
                }

                let detailed: DetailedManga
                do {
                    detailed = try await parser.parse(path: runtimePath)
                } catch {
                    Logger.bookPlugin.warning(
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
            Logger.bookPlugin.error("Failed to import file \(source.path): \(error)")
            throw error
        }

        Logger.bookPlugin.info("Imported file to \(destination.path(percentEncoded: false))")
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
