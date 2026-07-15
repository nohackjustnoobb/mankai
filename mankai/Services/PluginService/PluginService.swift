//
//  PluginService.swift
//  mankai
//
//  Created by Travis XU on 21/6/2025.
//

import Foundation

class PluginService: ObservableObject {
    /// The shared singleton instance of `PluginService`.
    static let shared = PluginService()

    private init() {
        Logger.pluginService.debug("Initializing PluginService")

        // Add built-in plugins
        _plugins[AppDirPlugin.shared.id] = AppDirPlugin.shared

        // Load JS plugins
        loadJsPlugins()

        // Load FS plugins
        loadFsPlugins()

        // Load HTTP plugins
        loadHttpPlugins()
    }

    private var _plugins: [String: Plugin] = [:]

    /// A list of all available plugins.
    var plugins: [Plugin] {
        return Array(_plugins.values)
    }

    private func loadJsPlugins() {
        Logger.pluginService.debug("Loading JS plugins")
        let jsPlugins = JsPlugin.loadPlugins()
        Logger.pluginService.info("Loaded \(jsPlugins.count) JS plugins")

        for jsPlugin in jsPlugins {
            if jsPlugin.shouldCache {
                _plugins[jsPlugin.id] = CacheWrapper(plugin: jsPlugin)
            } else {
                _plugins[jsPlugin.id] = jsPlugin
            }
        }

        Task {
            for jsPlugin in jsPlugins {
                await jsPlugin.checkForUpdates()
            }
        }
    }

    private func loadFsPlugins() {
        Logger.pluginService.debug("Loading FS plugins")
        let fsPlugins = ReadFsPlugin.loadPlugins()
        Logger.pluginService.info("Loaded \(fsPlugins.count) FS plugins")

        for fsPlugin in fsPlugins {
            if fsPlugin.shouldCache {
                _plugins[fsPlugin.id] = CacheWrapper(plugin: fsPlugin)
            } else {
                _plugins[fsPlugin.id] = fsPlugin
            }
        }
    }

    private func loadHttpPlugins() {
        Logger.pluginService.debug("Loading HTTP plugins")
        let httpPlugins = HttpPlugin.loadPlugins()
        Logger.pluginService.info("Loaded \(httpPlugins.count) HTTP plugins")

        for httpPlugin in httpPlugins {
            if httpPlugin.shouldCache {
                _plugins[httpPlugin.id] = CacheWrapper(plugin: httpPlugin)
            } else {
                _plugins[httpPlugin.id] = httpPlugin
            }
        }
    }

    /// Retrieves a plugin by its identifier.
    /// - Parameter id: The unique identifier of the plugin.
    /// - Returns: The `Plugin` instance if found, otherwise `nil`.
    func getPlugin(_ id: String) -> Plugin? {
        return _plugins[id]
    }

    /// Adds a new plugin to the service.
    /// - Parameter plugin: The `Plugin` instance to add.
    /// - Throws: An error if saving the plugin fails.
    func addPlugin(_ plugin: Plugin) throws {
        Logger.pluginService.debug("Adding plugin: \(plugin.id)")
        if plugin.shouldCache {
            _plugins[plugin.id] = CacheWrapper(plugin: plugin)
        } else {
            _plugins[plugin.id] = plugin
        }

        DispatchQueue.main.async {
            self.objectWillChange.send()
        }

        do {
            try plugin.savePlugin()
            Logger.pluginService.info("Plugin added successfully: \(plugin.id)")
        } catch {
            Logger.pluginService.error("Failed to save plugin: \(plugin.id)", error: error)
            throw error
        }
    }

    /// Removes a plugin from the service by its identifier.
    /// - Parameter id: The unique identifier of the plugin to remove.
    /// - Throws: An error if deleting the plugin fails.
    func removePlugin(_ id: String) throws {
        Logger.pluginService.debug("Removing plugin: \(id)")
        if let plugin = _plugins.removeValue(forKey: id) {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }

            do {
                try plugin.deletePlugin()
                Logger.pluginService.info("Plugin removed successfully: \(id)")
            } catch {
                Logger.pluginService.error("Failed to delete plugin: \(id)", error: error)
                throw error
            }
        } else {
            Logger.pluginService.warning("Plugin not found for removal: \(id)")
        }
    }
}
