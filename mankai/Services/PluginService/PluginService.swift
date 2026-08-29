//
//  PluginService.swift
//  mankai
//
//  Created by Travis XU on 21/6/2025.
//

import Foundation

enum PluginAddConflictResolution: Equatable {
    case reject
    case overwrite
}

final class PluginService: ObservableObject {
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
    var plugins: [Plugin] { return Array(_plugins.values) }

    private func loadJsPlugins() {
        Logger.pluginService.debug("Loading JS plugins")
        let jsPlugins = JsPlugin.loadPlugins()
        Logger.pluginService.info("Loaded \(jsPlugins.count) JS plugins")

        for jsPlugin in jsPlugins { _plugins[jsPlugin.id] = wrap(jsPlugin) }

        Task { for jsPlugin in jsPlugins { await jsPlugin.checkForUpdates() } }
    }

    private func loadFsPlugins() {
        Logger.pluginService.debug("Loading FS plugins")
        let fsPlugins = ReadFsPlugin.loadPlugins()
        Logger.pluginService.info("Loaded \(fsPlugins.count) FS plugins")

        for fsPlugin in fsPlugins { _plugins[fsPlugin.id] = wrap(fsPlugin) }
    }

    private func loadHttpPlugins() {
        Logger.pluginService.debug("Loading HTTP plugins")
        let httpPlugins = HttpPlugin.loadPlugins()
        Logger.pluginService.info("Loaded \(httpPlugins.count) HTTP plugins")

        for httpPlugin in httpPlugins { _plugins[httpPlugin.id] = wrap(httpPlugin) }

        Task { for httpPlugin in httpPlugins { await httpPlugin.checkForUpdates() } }
    }

    private func wrap(_ plugin: Plugin) -> Plugin {
        var wrappedPlugin = plugin

        if plugin.cooldown != nil { wrappedPlugin = CooldownWrapper.wrapping(wrappedPlugin) }

        if plugin.shouldCache { wrappedPlugin = CacheWrapper.wrapping(wrappedPlugin) }

        return wrappedPlugin
    }

    /// Retrieves a plugin by its identifier.
    /// - Parameter id: The unique identifier of the plugin.
    /// - Returns: The `Plugin` instance if found, otherwise `nil`.
    func getPlugin(_ id: String) -> Plugin? { return _plugins[id] }

    /// Adds a new plugin to the service.
    /// - Parameters:
    ///   - plugin: The `Plugin` instance to add.
    ///   - conflictResolution: How to handle an existing plugin with the same identifier.
    /// - Throws: An error if saving the plugin fails.
    func addPlugin(_ plugin: Plugin, conflictResolution: PluginAddConflictResolution = .reject)
        throws
    {
        Logger.pluginService.debug("Adding plugin: \(plugin.id)")

        let existingPlugin = _plugins[plugin.id]
        if existingPlugin != nil, conflictResolution == .reject {
            Logger.pluginService.warning("Plugin ID already exists: \(plugin.id)")
            throw MankaiErrorCode.pluginDuplicateId.makeError(
                messageArguments: [plugin.id],
                additionalUserInfo: [MankaiErrorUserInfoKey.pluginId: plugin.id])
        }

        do {
            if let existingPlugin { try existingPlugin.deletePlugin() }
            try plugin.savePlugin()
            _plugins[plugin.id] = wrap(plugin)

            DispatchQueue.main.async { self.objectWillChange.send() }

            Logger.pluginService.info("Plugin added successfully: \(plugin.id)")
        } catch {
            if let existingPlugin {
                do { try existingPlugin.savePlugin() } catch {
                    Logger.pluginService.error(
                        "Failed to restore overwritten plugin: \(plugin.id)", error: error)
                }
            }
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
            DispatchQueue.main.async { self.objectWillChange.send() }

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
