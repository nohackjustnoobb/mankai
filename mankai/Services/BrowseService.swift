//
//  BrowseService.swift
//  mankai
//
//  Created by Travis XU on 13/7/2026.
//

import Foundation

enum EntityType {
    case book(manga: DetailedManga)
    case directory(path: String)
}

protocol Browsable {
    func getEntities(path: String?) async throws -> [EntityType]

    var systemImageName: String? { get }
}

typealias BrowsablePlugin = Browsable & Plugin

class BrowseService: ObservableObject {
    static let shared = BrowseService()

    private init() {
        Logger.browseService.debug("Initializing BrowseService")

        // Add built-in plugins
        _plugins[AppDirBookPlugin.shared.id] = AppDirBookPlugin.shared

        // Load plugins from db
        loadBookPlugins()
    }

    private var _plugins: [String: BrowsablePlugin] = [:]

    /// A list of all available plugins.
    var plugins: [BrowsablePlugin] {
        return Array(_plugins.values)
    }

    private func loadBookPlugins() {
        Logger.browseService.debug("Loading book plugins")
        let bookPlugins = BookPlugin.loadPlugins()
        Logger.browseService.info("Loaded \(bookPlugins.count) book plugins")

        for bookPlugin in bookPlugins {
            _plugins[bookPlugin.id] = bookPlugin
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
