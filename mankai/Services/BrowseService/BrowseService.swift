//
//  BrowseService.swift
//  mankai
//
//  Created by Travis XU on 13/7/2026.
//

import Foundation
import SwiftUI

enum EntityType {
    case book(path: String, fileType: String)
    case directory(path: String)

    /// Name of the entity in the browse view.
    var name: String {
        switch self {
        case .book(let path, _):
            return (path as NSString).lastPathComponent
        case .directory(let path):
            return (path as NSString).lastPathComponent
        }
    }

    /// Display name for a file after its manga metadata has been parsed.
    func name(using manga: DetailedManga?) -> String {
        switch self {
        case .book(let path, _):
            guard let manga else {
                return (path as NSString).lastPathComponent
            }

            let allChapters = manga.chapters.flatMap(\.chapters)
            if allChapters.count == 1,
                let chapterTitle = allChapters.first?.title
            {
                return chapterTitle
            }
            return manga.title ?? (path as NSString).lastPathComponent
        case .directory(let path):
            return (path as NSString).lastPathComponent
        }
    }

    /// The actual file name of the entity.
    var fileName: String {
        switch self {
        case .book(let path, _):
            return (path as NSString).lastPathComponent
        case .directory(let path):
            return (path as NSString).lastPathComponent
        }
    }
}

protocol Browsable {
    /// The name of the system image used to represent this plugin.
    var systemImageName: String { get }

    /// The color of the system image used to represent this plugin.
    var systemImageColor: Color { get }

    /// The file extensions supported by this plugin.
    var supportedExtensions: [String] { get }

    /// The directory inside the plugin used for files imported via the file importer.
    var importsPath: String { get }

    /// Returns the entities at the given path.
    func getEntities(path: String?) async throws -> [EntityType]

    /// Parses a supported manga file at the given path.
    func parseFile(path: String, fileType: String) async throws -> DetailedManga

    /// Returns the absolute filesystem URL for the given relative path, if the
    /// plugin is backed by a local filesystem directory. Returns `nil` for
    /// non-filesystem plugins.
    /// - Parameter path: A path relative to the plugin's root, or `nil` for the root.
    func absoluteURL(for path: String?) -> URL?

    /// Imports a file from the given URL into the plugin's `importsDir`.
    ///
    /// The caller is responsible for ensuring the source resource is accessible
    /// (e.g. by starting security-scoped access if needed).
    ///
    /// - Parameter source: The URL of the file to import.
    func importFile(from source: URL) async throws
}

typealias BrowsablePlugin = Browsable & Plugin

final class BrowseService: ObservableObject {
    static let shared = BrowseService()

    private init() {
        Logger.browseService.debug("Initializing BrowseService")

        // Add built-in plugins
        _plugins[AppDirBrowsablePlugin.shared.id] = AppDirBrowsablePlugin.shared

        // Load plugins from db
        loadFsBrowablePlugins()
        loadSmbBrowsablePlugins()
        loadWebDavBrowsablePlugins()
    }

    private var _plugins: [String: BrowsablePlugin] = [:]

    /// A list of all available plugins, with `AppDirBrowsablePlugin` always placed first.
    var plugins: [BrowsablePlugin] {
        let appDir = AppDirBrowsablePlugin.shared
        let others = _plugins.values.filter { $0.id != appDir.id }.sorted { $0.id < $1.id }
        return [appDir] + others
    }

    private func loadFsBrowablePlugins() {
        Logger.browseService.debug("Loading fs browsable plugins")
        let fsBrowsablePlugins = FsBrowsablePlugin.loadPlugins()
        Logger.browseService.info("Loaded \(fsBrowsablePlugins.count) fs browsable plugins")

        for plugin in fsBrowsablePlugins {
            _plugins[plugin.id] = plugin
        }
    }

    private func loadSmbBrowsablePlugins() {
        Logger.browseService.debug("Loading SMB browsable plugins")
        let smbBrowsablePlugins = SmbBrowsablePlugin.loadPlugins()
        Logger.browseService.info("Loaded \(smbBrowsablePlugins.count) SMB browsable plugins")

        for plugin in smbBrowsablePlugins {
            _plugins[plugin.id] = plugin
        }
    }

    private func loadWebDavBrowsablePlugins() {
        Logger.browseService.debug("Loading WebDAV browsable plugins")
        let webDavBrowsablePlugins = WebDavBrowsablePlugin.loadPlugins()
        Logger.browseService.info(
            "Loaded \(webDavBrowsablePlugins.count) WebDAV browsable plugins")

        for plugin in webDavBrowsablePlugins {
            _plugins[plugin.id] = plugin
        }
    }

    /// Retrieves a plugin by its identifier.
    /// - Parameter id: The unique identifier of the plugin.
    /// - Returns: The `BrowsablePlugin` instance if found, otherwise `nil`.
    func getPlugin(_ id: String) -> BrowsablePlugin? {
        return _plugins[id]
    }

    /// Adds a new plugin to the service.
    /// - Parameter plugin: The `BrowsablePlugin` instance to add.
    /// - Throws: An error if saving the plugin fails.
    func addPlugin(_ plugin: BrowsablePlugin) throws {
        Logger.browseService.debug("Adding plugin: \(plugin.id)")
        _plugins[plugin.id] = plugin

        DispatchQueue.main.async {
            self.objectWillChange.send()
        }

        do {
            try plugin.savePlugin()
            Logger.browseService.info("Plugin added successfully: \(plugin.id)")
        } catch {
            Logger.browseService.error("Failed to save plugin: \(plugin.id)", error: error)
            throw error
        }
    }

    /// Removes a plugin from the service by its identifier.
    /// - Parameter id: The unique identifier of the plugin to remove.
    /// - Throws: An error if deleting the plugin fails.
    func removePlugin(_ id: String) throws {
        Logger.browseService.debug("Removing plugin: \(id)")
        if let plugin = _plugins.removeValue(forKey: id) {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }

            do {
                try plugin.deletePlugin()
                Logger.browseService.info("Plugin removed successfully: \(id)")
            } catch {
                Logger.browseService.error("Failed to delete plugin: \(id)", error: error)
                throw error
            }
        } else {
            Logger.browseService.warning("Plugin not found for removal: \(id)")
        }
    }
}
