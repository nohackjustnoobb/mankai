//
//  Plugin.swift
//  mankai
//
//  Created by Travis XU on 21/6/2025.
//

import Foundation

enum ConfigType: String {
    case text
    case password
    case number
    case boolean
    case select

    func parseValue(_ stringValue: String) -> Any {
        switch self {
        case .boolean:
            return stringValue.lowercased() == "true" || stringValue == "1"
        case .number:
            if let intValue = Int(stringValue) {
                return intValue
            }
            return Double(stringValue) ?? stringValue
        case .text, .password, .select:
            return stringValue
        }
    }
}

struct Config {
    var key: String
    var name: String
    var description: String?
    var type: ConfigType
    var defaultValue: Any
    var options: [String]?
}

struct ConfigValue {
    var key: String
    var value: Any
}

class Plugin: Identifiable, ObservableObject {
    // MARK: - Metadata

    /// The unique identifier of the plugin.
    /// - Returns: A unique string identifier.
    var id: String {
        fatalError("Not Implemented")
    }

    var name: String? {
        nil
    }

    var version: String? {
        nil
    }

    var tags: [String] {
        []
    }

    var description: String? {
        nil
    }

    var authors: [String] {
        []
    }

    var repository: String? {
        nil
    }

    var availableGenres: [Genre] {
        []
    }

    var configs: [Config] {
        []
    }

    var shouldSync: Bool {
        true
    }

    var shouldCache: Bool {
        false
    }

    // MARK: - Config Values

    lazy var _configValues: [String: ConfigValue] = {
        var _configValues: [String: ConfigValue] = [:]

        for config in configs {
            _configValues[config.key] = ConfigValue(
                key: config.key, value: config.defaultValue
            )
        }

        return _configValues
    }()

    var configValues: [ConfigValue] {
        Array(_configValues.values)
    }

    // MARK: - Methods

    func getConfig(_ key: String) -> Any {
        _configValues[key]!.value
    }

    func setConfig(key: String, value: Any) throws {
        _configValues[key] = ConfigValue(key: key, value: value)

        DispatchQueue.main.async {
            self.objectWillChange.send()
        }

        try savePlugin()
    }

    func resetConfigs() throws {
        _configValues = [:]

        for config in configs {
            _configValues[config.key] = ConfigValue(
                key: config.key, value: config.defaultValue
            )
        }

        DispatchQueue.main.async {
            self.objectWillChange.send()
        }

        try savePlugin()
    }

    // MARK: - Abstract Methods

    /// Saves the plugin configuration or state.
    /// - Throws: An error if saving fails.
    func savePlugin() throws {
        fatalError("Not Implemented")
    }

    /// Deletes the plugin and cleans up resources.
    /// - Throws: An error if deletion fails.
    func deletePlugin() throws {
        fatalError("Not Implemented")
    }

    /// Checks if the plugin is currently online and reachable.
    /// - Returns: `true` if online, `false` otherwise.
    /// - Throws: An error if the check fails.
    func isOnline() async throws -> Bool {
        fatalError("Not Implemented")
    }

    /// Gets search suggestions based on a query.
    /// - Parameter query: The search query string.
    /// - Returns: A list of suggested search terms.
    /// - Throws: An error if the request fails.
    func getSuggestions(_: String) async throws -> [String] {
        fatalError("Not Implemented")
    }

    /// Searches for manga based on a query.
    /// - Parameters:
    ///   - query: The search query string.
    ///   - page: The page number for pagination.
    /// - Returns: A list of `Manga` objects matching the query.
    /// - Throws: An error if the search fails.
    func search(_: String, page _: UInt) async throws -> [Manga] {
        fatalError("Not Implemented")
    }

    /// Retrieves a list of manga based on optional filters.
    /// - Parameters:
    ///   - page: The page number for pagination.
    ///   - genre: The genre to filter by.
    ///   - status: The status to filter by.
    /// - Returns: A list of `Manga` objects.
    /// - Throws: An error if the request fails.
    func getList(page _: UInt, genre _: Genre, status _: Status) async throws -> [Manga] {
        fatalError("Not Implemented")
    }

    /// Retrieves details for multiple mangas by their IDs.
    /// - Parameter ids: A list of manga IDs.
    /// - Returns: A list of `Manga` objects.
    /// - Throws: An error if the request fails.
    func getMangas(_: [String]) async throws -> [Manga] {
        fatalError("Not Implemented")
    }

    /// Retrieves detailed information for a specific manga.
    /// - Parameter id: The ID of the manga.
    /// - Returns: A `DetailedManga` object.
    /// - Throws: An error if the request fails.
    func getDetailedManga(_: String) async throws -> DetailedManga {
        fatalError("Not Implemented")
    }

    /// Retrieves the list of image URLs for a specific chapter.
    /// - Parameters:
    ///   - manga: The manga containing the chapter.
    ///   - chapter: The chapter to retrieve images for.
    /// - Returns: A list of image URLs.
    /// - Throws: An error if the request fails.
    func getChapter(manga _: DetailedManga, chapter _: Chapter) async throws -> [String] {
        fatalError("Not Implemented")
    }

    /// Retrieves image data from a URL.
    /// - Parameter url: The URL of the image.
    /// - Returns: The image data.
    /// - Throws: An error if the request fails.
    func getImage(_: String) async throws -> Data {
        fatalError("Not Implemented")
    }
}

extension Plugin {
    func getManga(id: String) async throws -> Manga {
        let mangas = try await getMangas([id])

        if let manga = mangas.first {
            return manga
        } else {
            throw NSError(
                domain: "Plugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "mangaNotFound")]
            )
        }
    }
}
