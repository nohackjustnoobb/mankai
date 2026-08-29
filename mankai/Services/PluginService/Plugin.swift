//
//  Plugin.swift
//  mankai
//
//  Created by Travis XU on 21/6/2025.
//

import Foundation
import ReerCodable

enum ConfigType: String, Codable {
    case text
    case password
    case number
    case boolean
    case select

    func parseValue(_ stringValue: String) -> Any {
        let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self { case .boolean: return trimmed.lowercased() == "true" || trimmed == "1"
            case .number:
                if let intValue = Int(trimmed) { return intValue }
                return Double(trimmed) ?? trimmed
            case .text, .password, .select: return trimmed
        }
    }
}

@Codable struct Config {
    var key: String
    var name: String
    var description: String?
    var type: ConfigType
    var options: [String]?

    @CodingKey("defaultValue") private var codedDefaultValue: AnyCodable?

    var defaultValue: Any {
        get { codedDefaultValue?.value ?? NSNull() }
        set { codedDefaultValue = AnyCodable(newValue) }
    }

    init(
        key: String, name: String, description: String? = nil, type: ConfigType, defaultValue: Any,
        options: [String]? = nil
    ) {
        self.key = key
        self.name = name
        self.description = description
        self.type = type
        self.options = options
        codedDefaultValue = AnyCodable(defaultValue)
    }
}

@Codable struct ConfigValue {
    var key: String

    @CodingKey("value") private var codedValue: AnyCodable

    var value: Any {
        get { codedValue.value }
        set { codedValue = AnyCodable(newValue) }
    }

    init(key: String, value: Any) {
        self.key = key
        codedValue = AnyCodable(value)
    }
}

struct Cooldown: Codable {
    var `default`: Int?
    var getImage: Int?
    var getImageConcurrency: Int?
}

/// Features that a plugin can support.
///
/// Plugins currently support every capability by default.
/// A plugin can later provide a smaller list to disable features it does not implement.
enum PluginCapability: String, Codable, CaseIterable {
    case onlineCheck
    case suggestions
    case list
    case listByGenre
    case listByStatus
    case search
    case searchByGenre
    case searchByStatus
    case searchByAuthor
    case mangaDetails
    case batchMangas
    case chapter
    case image
}

class Plugin: Identifiable, ObservableObject {
    // MARK: - Metadata

    /// The unique identifier of the plugin.
    /// - Returns: A unique string identifier.
    var id: String { fatalError("Not Implemented") }

    var name: String? { nil }

    var version: String? { nil }

    var tags: [String] { [] }

    var description: String? { nil }

    var authors: [String] { [] }

    var repository: String? { nil }

    var availableGenres: [Genre] { [] }

    var configs: [Config] { [] }

    var cooldown: Cooldown? { nil }

    /// Operations supported by the plugin.
    ///
    /// Plugins that do not provide capability metadata support every operation by default.
    /// Plugins can override this with a smaller list.
    var capabilities: [PluginCapability] { PluginCapability.allCases }

    /// Whether manga sourced from this plugin should be synced across devices.
    var shouldSync: Bool { true }

    /// Whether response data from this plugin should be cached.
    var shouldCache: Bool { false }

    /// Whether manga sourced from this plugin can be downloaded for offline access.
    var canDownload: Bool { true }

    // MARK: - Config Values

    lazy var _configValues: [String: ConfigValue] = {
        var _configValues: [String: ConfigValue] = [:]

        for config in configs {
            _configValues[config.key] = ConfigValue(key: config.key, value: config.defaultValue)
        }

        return _configValues
    }()

    var configValues: [ConfigValue] { Array(_configValues.values) }

    // MARK: - Methods

    func getConfig(_ key: String) -> Any { _configValues[key]!.value }

    func setConfig(key: String, value: Any) throws {
        _configValues[key] = ConfigValue(key: key, value: value)

        DispatchQueue.main.async { self.objectWillChange.send() }

        try savePlugin()
    }

    func resetConfigs() throws {
        _configValues = [:]

        for config in configs {
            _configValues[config.key] = ConfigValue(key: config.key, value: config.defaultValue)
        }

        DispatchQueue.main.async { self.objectWillChange.send() }

        try savePlugin()
    }

    // MARK: - Abstract Methods

    /// Saves the plugin configuration or state.
    /// - Throws: An error if saving fails.
    func savePlugin() throws { fatalError("Not Implemented") }

    /// Deletes the plugin and cleans up resources.
    /// - Throws: An error if deletion fails.
    func deletePlugin() throws { fatalError("Not Implemented") }

    /// Checks if the plugin is currently online and reachable.
    /// - Returns: `true` if online, `false` otherwise.
    /// - Throws: An error if the check fails.
    func isOnline() async throws -> Bool { fatalError("Not Implemented") }

    /// Gets search suggestions based on a query.
    /// - Parameter query: The search query string.
    /// - Returns: A list of suggested search terms.
    /// - Throws: An error if the request fails.
    func getSuggestions(_: String) async throws -> [String] { fatalError("Not Implemented") }

    /// Searches for manga based on a query.
    /// - Parameters:
    ///   - query: The search query string.
    ///   - page: The page number for pagination.
    ///   - genre: The genre to filter by.
    ///   - status: The status to filter by.
    ///   - isAuthor: Whether to search the author field instead of the title field.
    /// - Returns: A list of `Manga` objects matching the query.
    /// - Throws: An error if the search fails.
    func search(_: String, page _: UInt, genre _: Genre, status _: Status, isAuthor _: Bool = false)
        async throws -> [Manga]
    { fatalError("Not Implemented") }

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
    func getMangas(_: [String]) async throws -> [Manga] { fatalError("Not Implemented") }

    /// Retrieves detailed information for a specific manga.
    /// - Parameter id: The ID of the manga.
    /// - Returns: A `DetailedManga` object.
    /// - Throws: An error if the request fails.
    func getDetailedManga(_: String) async throws -> DetailedManga { fatalError("Not Implemented") }

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
    func getImage(_: String) async throws -> Data { fatalError("Not Implemented") }
}

extension Plugin {
    /// Returns whether the plugin advertises support for a capability.
    func supports(_ capability: PluginCapability) -> Bool { capabilities.contains(capability) }

    /// Returns whether the plugin can service a list request with the supplied filters.
    /// Filter capabilities augment, rather than replace, the base list capability.
    func supportsList(genre: Genre = .all, status: Status = .any) -> Bool {
        guard supports(.list) else { return false }

        if genre != .all, !supports(.listByGenre) { return false }
        if status != .any, !supports(.listByStatus) { return false }

        return true
    }

    /// Returns whether the plugin can service a search request with the supplied filters.
    /// Filter capabilities augment, rather than replace, the base search capability.
    func supportsSearch(isAuthor: Bool = false, genre: Genre = .all, status: Status = .any) -> Bool
    {
        guard supports(.search) else { return false }

        if isAuthor, !supports(.searchByAuthor) { return false }
        if genre != .all, !supports(.searchByGenre) { return false }
        if status != .any, !supports(.searchByStatus) { return false }

        return true
    }

    /// Whether the source can resolve chapters and fetch their images.
    var supportsRemoteReading: Bool { supports(.chapter) && supports(.image) }

    /// Whether new offline downloads can be created from this source.
    var supportsDownloads: Bool { canDownload && supportsRemoteReading }

    func getManga(id: String) async throws -> Manga {
        let mangas = try await getMangas([id])

        if let manga = mangas.first {
            return manga
        } else {
            throw MankaiErrorCode.pluginMangaNotFound.makeError()
        }
    }
}
