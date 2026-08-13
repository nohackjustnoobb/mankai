//
//  FsBrowsablePlugin.swift
//  mankai
//
//  Created by Travis XU on 13/7/2026.
//

import Foundation
import GRDB

class FsBrowsablePlugin: GenericBrowsablePlugin {
    override var name: String? {
        pluginName ?? dirName
    }

    let url: URL
    private let pluginName: String?
    private let _shouldSync: Bool
    private var isAccessingSecurityScopedResource = false
    private lazy var dirName: String = url.lastPathComponent

    private var importsDir: URL {
        url.appendingPathComponent(importsPath, isDirectory: true)
    }

    init(url: URL, id: String, name: String?, shouldSync: Bool = true) {
        Logger.fsBrowsablePlugin.debug("Initializing FsBrowsablePlugin with url: \(url.path)")
        self.url = url
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        pluginName = trimmedName?.isEmpty == false ? trimmedName : nil
        _shouldSync = shouldSync
        super.init(id: id)

        if !(self is AppDirBrowsablePlugin) {
            isAccessingSecurityScopedResource = url.startAccessingSecurityScopedResource()
            if !isAccessingSecurityScopedResource {
                Logger.fsBrowsablePlugin.error(
                    "Failed to start accessing security scoped resource for plugin: \(id)"
                )
            }
        }
    }

    convenience init(url: URL, name: String?) throws {
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
        let shouldSync: Bool
        if fileManager.fileExists(atPath: idFile.path) {
            id = try String(contentsOf: idFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            shouldSync = true
        } else {
            id = UUID().uuidString
            do {
                try id.write(to: idFile, atomically: true, encoding: .utf8)
                shouldSync = true
            } catch {
                Logger.fsBrowsablePlugin.warning(
                    "Failed to write .mankai for plugin \(id), using a local-only ID: \(error)"
                )
                shouldSync = false
            }
        }

        self.init(url: url, id: id, name: name, shouldSync: shouldSync)
    }

    deinit {
        if isAccessingSecurityScopedResource {
            url.stopAccessingSecurityScopedResource()
        }
    }

    static func loadPlugins() -> [FsBrowsablePlugin] {
        Logger.fsBrowsablePlugin.debug("Loading book plugins")
        guard let dbPool = DbService.shared.appDb else {
            Logger.fsBrowsablePlugin.error("Database not available")
            return []
        }

        var models: [FsBrowsablePluginModel]
        do {
            models = try dbPool.read { db in
                try FsBrowsablePluginModel.fetchAll(db)
            }
        } catch {
            Logger.fsBrowsablePlugin.error("Failed to fetch FsBrowsablePluginModels: \(error)")
            return []
        }

        var results: [FsBrowsablePlugin] = []
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
                    Logger.fsBrowsablePlugin.warning(
                        "Bookmark data is stale for plugin: \(model.id)")
                    let newBookmarkData = try url.bookmarkData(
                        options: .minimalBookmark,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    model.bookmarkData = newBookmarkData
                    try dbPool.write { db in
                        try model.update(db)
                    }
                }

                guard url.startAccessingSecurityScopedResource() else {
                    Logger.fsBrowsablePlugin.error(
                        "Failed to start accessing security scoped resource for plugin: \(model.id)"
                    )
                    continue
                }
                defer {
                    url.stopAccessingSecurityScopedResource()
                }

                results.append(
                    FsBrowsablePlugin(
                        url: url,
                        id: model.id,
                        name: model.name,
                        shouldSync: model.shouldSync
                    ))
            } catch {
                Logger.fsBrowsablePlugin.error(
                    "Failed to resolve bookmark for plugin \(model.id): \(error)"
                )
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
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try db.write { db in
            try FsBrowsablePluginModel(
                id: id,
                name: pluginName,
                bookmarkData: bookmarkData,
                shouldSync: shouldSync
            ).save(db)
        }
    }

    override var shouldSync: Bool {
        _shouldSync
    }

    override func deletePlugin() throws {
        Logger.fsBrowsablePlugin.debug("Deleting plugin: \(id)")
        guard let db = DbService.shared.appDb else {
            throw MankaiErrorCode.browseFilesystemDatabaseNotAvailable.makeError()
        }

        _ = try db.write { db in
            try FsBrowsablePluginModel.deleteOne(db, key: id)
        }
        try super.deletePlugin()
    }

    // MARK: - Filesystem backend hooks

    override func entries(path: String?) async throws -> [BrowsableEntry] {
        let target = try sourceURL(for: path)
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]
        let fileManager = FileManager.default
        let entries = try fileManager.contentsOfDirectory(
            at: target,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        let basePath = url.standardizedFileURL.path
        return try entries.compactMap { entry in
            let values = try entry.resourceValues(forKeys: resourceKeys)
            let standardizedPath = entry.standardizedFileURL.path
            let runtimePath: String
            if standardizedPath.hasPrefix(basePath) {
                let dropped = String(standardizedPath.dropFirst(basePath.count))
                runtimePath = dropped.hasPrefix("/") ? String(dropped.dropFirst()) : dropped
            } else {
                runtimePath = entry.lastPathComponent
            }

            guard values.isDirectory == true || values.isRegularFile == true else { return nil }
            return BrowsableEntry(
                path: runtimePath,
                isDirectory: values.isDirectory == true,
                isRegularFile: values.isRegularFile == true
            )
        }
    }

    override func parserFile(relativePath: String, cacheKey: String) async throws -> ParserFile {
        try FsParserFile(cacheKey: cacheKey, url: sourceURL(for: relativePath))
    }

    override func hashFile(relativePath: String) async throws -> String {
        let fileURL = try sourceURL(for: relativePath)
        return try BrowsableFileUtilities.sha256(of: fileURL)
    }

    override func absoluteURL(for path: String?) -> URL? {
        try? sourceURL(for: path)
    }

    private func sourceURL(for relativePath: String?) throws -> URL {
        guard let relativePath, !relativePath.isEmpty else { return url }

        let rootURL = url.standardizedFileURL
        let sourceURL = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : "\(rootURL.path)/"
        guard sourceURL.path.hasPrefix(rootPath) else {
            Logger.fsBrowsablePlugin.error("Path escapes plugin root: \(relativePath)")
            throw MankaiErrorCode.browseFilesystemInvalidMangaMeta.makeError()
        }
        return sourceURL
    }

    override func importFile(from source: URL) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: importsDir, withIntermediateDirectories: true)

        let baseName = source.lastPathComponent
        var destination = importsDir.appendingPathComponent(baseName)
        if fileManager.fileExists(atPath: destination.path) {
            let stem = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension
            var counter = 1
            repeat {
                let candidate =
                    ext.isEmpty
                    ? "\(stem) (\(counter))"
                    : "\(stem) (\(counter)).\(ext)"
                destination = importsDir.appendingPathComponent(candidate)
                counter += 1
            } while fileManager.fileExists(atPath: destination.path)
        }

        let needsScopeAccess = source.startAccessingSecurityScopedResource()
        defer {
            if needsScopeAccess {
                source.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            Logger.fsBrowsablePlugin.error("Failed to import file \(source.path): \(error)")
            throw error
        }
    }
}
