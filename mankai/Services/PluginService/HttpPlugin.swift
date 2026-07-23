//
//  HttpPlugin.swift
//  mankai
//
//  Created by Travis XU on 30/1/2026.
//

import Foundation
import GRDB

class HttpPlugin: Plugin {
    private var _id: String
    private var _name: String?
    private var _version: String?
    private var _description: String?
    private var _authors: [String]
    private var _repository: String?
    private var _availableGenres: [Genre]

    override var id: String {
        _id
    }

    override var name: String? {
        _name
    }

    override var version: String? {
        _version
    }

    override var description: String? {
        _description
    }

    override var authors: [String] {
        _authors
    }

    override var repository: String? {
        _repository
    }

    override var availableGenres: [Genre] {
        _availableGenres
    }

    override var configs: [Config] {
        [
            Config(key: "username", name: "username", type: .text, defaultValue: ""),
            Config(key: "password", name: "password", type: .password, defaultValue: ""),
        ]
    }

    private var _authenticationEnabled: Bool
    var authenticationEnabled: Bool {
        _authenticationEnabled
    }

    private var baseUrl: String
    lazy var authManager: AuthManager = .init(id: id)
    private var isMetaUpdated: Bool = false

    private var setupTask: Task<Void, Error>?
    private let setupLock = NSLock()

    override var tags: [String] {
        [String(localized: "http")]
    }

    override var shouldCache: Bool {
        true
    }

    // MARK: - Init

    required init(
        id: String, baseUrl: String, authenticationEnabled: Bool, name: String? = nil,
        version: String? = nil, description: String? = nil,
        authors: [String] = [],
        repository: String? = nil,
        availableGenres: [Genre] = []
    ) {
        Logger.httpPlugin.debug("Initializing HttpPlugin: \(id)")
        _id = id
        self.baseUrl = baseUrl
        if self.baseUrl.hasSuffix("/") {
            self.baseUrl.removeLast()
        }
        _authenticationEnabled = authenticationEnabled
        _name = name
        _version = version
        _description = description
        _authors = authors
        _repository = repository
        _availableGenres = availableGenres
    }

    private func setConfigValues(_ configValues: [ConfigValue]) {
        for configValue in configValues {
            _configValues[configValue.key] = configValue
        }
    }

    static func fromJson(baseUrl: String, _ json: [String: Any]) -> HttpPlugin? {
        guard let id = json["id"] as? String else { return nil }
        guard let authenticationEnabled = json["authenticationEnabled"] as? Bool else { return nil }
        let editorEnabled = json["editorEnabled"] as? Bool ?? false
        let name = json["name"] as? String
        let version = json["version"] as? String
        let description = json["description"] as? String
        let authors = json["authors"] as? [String] ?? []
        let repository = json["repository"] as? String
        let availableGenres =
            (json["availableGenres"] as? [String])?.compactMap { Genre(rawValue: $0) } ?? []

        if editorEnabled, !(self is EditableHttpPlugin.Type) {
            return EditableHttpPlugin(
                id: id, baseUrl: baseUrl, authenticationEnabled: authenticationEnabled, name: name,
                version: version, description: description, authors: authors,
                repository: repository, availableGenres: availableGenres
            )
        }

        if !editorEnabled, self is EditableHttpPlugin.Type {
            Logger.httpPlugin.warning(
                "Plugin \(id) is not editable but EditableHttpPlugin is being used. This may cause issues."
            )
            return nil
        }

        return self.init(
            id: id, baseUrl: baseUrl, authenticationEnabled: authenticationEnabled, name: name,
            version: version, description: description, authors: authors,
            repository: repository, availableGenres: availableGenres
        )
    }

    static func fromUrl(_ url: URL) async -> HttpPlugin? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else {
            return nil
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else {
            return nil
        }

        var baseUrl = url.absoluteString
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = nil
            components.fragment = nil
            baseUrl = components.string ?? url.absoluteString
        }

        guard let plugin = fromJson(baseUrl: baseUrl, json) else {
            return nil
        }

        let configMap = Dictionary(uniqueKeysWithValues: plugin.configs.map { ($0.key, $0) })
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        var matchedConfigValues: [ConfigValue] = []
        for item in queryItems {
            guard let config = configMap[item.name] else { continue }
            let parsedValue = config.type.parseValue(item.value ?? "")
            matchedConfigValues.append(ConfigValue(key: item.name, value: parsedValue))
        }

        if !matchedConfigValues.isEmpty {
            plugin.setConfigValues(matchedConfigValues)
        }

        return plugin
    }

    static func fromDataModel(_ httpPluginModel: HttpPluginModel) -> HttpPlugin? {
        guard let metaData = httpPluginModel.meta.data(using: .utf8),
              let metaJson = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any]
        else {
            return nil
        }

        // Parse config values if they exist
        var configValues: [ConfigValue]? = nil
        if let configValuesData = httpPluginModel.configValues.data(using: .utf8),
           let configValuesArray = try? JSONSerialization.jsonObject(with: configValuesData)
           as? [[String: Any]]
        {
            configValues = configValuesArray.compactMap { dict in
                guard let key = dict["key"] as? String,
                      let value = dict["value"]
                else {
                    return nil
                }

                return ConfigValue(key: key, value: value)
            }
        }

        let plugin = fromJson(baseUrl: httpPluginModel.baseUrl, metaJson)

        // Update config values if they exist
        if let configValues = configValues,
           let plugin = plugin
        {
            plugin.setConfigValues(configValues)
        }

        return plugin
    }

    static func loadPlugins() -> [HttpPlugin] {
        Logger.httpPlugin.debug("Loading HTTP plugins")
        guard let dbPool = DbService.shared.appDb else {
            Logger.httpPlugin.error("Database not available")
            return []
        }

        var results: [HttpPlugin] = []

        do {
            try dbPool.read { db in
                let httpPluginModels = try HttpPluginModel.fetchAll(db)

                for httpPluginModel in httpPluginModels {
                    if let httpPlugin = HttpPlugin.fromDataModel(httpPluginModel) {
                        results.append(httpPlugin)
                    }
                }
            }
        } catch {
            Logger.httpPlugin.error("Failed to load plugins from GRDB", error: error)
        }

        return results
    }

    // MARK: - Private Methods

    func setup() async throws {
        try await getOrCreateSetupTask().value
    }

    private func getOrCreateSetupTask() -> Task<Void, Error> {
        setupLock.lock()
        defer { setupLock.unlock() }

        if let existingTask = setupTask {
            return existingTask
        }

        let newTask = Task {
            defer { setupTask = nil }
            try await performSetup()
        }
        setupTask = newTask
        return newTask
    }

    private func performSetup() async throws {
        // update meta
        if !isMetaUpdated {
            let metaUrl = URL(string: baseUrl)
            guard let metaUrl = metaUrl else {
                throw NSError(
                    domain: "HttpPlugin", code: 0,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "invalidUrl")]
                )
            }
            let (metaData, _) = try await URLSession.shared.data(from: metaUrl)
            let metaJson = try JSONSerialization.jsonObject(with: metaData) as? [String: Any]
            guard let metaJson = metaJson else { return }

            _name = metaJson["name"] as? String
            _version = metaJson["version"] as? String
            _description = metaJson["description"] as? String
            _authors = metaJson["authors"] as? [String] ?? []
            _repository = metaJson["repository"] as? String
            _availableGenres =
                (metaJson["availableGenres"] as? [String])?.compactMap { Genre(rawValue: $0) } ?? []
            _authenticationEnabled = metaJson["authenticationEnabled"] as? Bool ?? false

            try savePlugin()
            isMetaUpdated = true
        }

        guard authenticationEnabled else { return }

        let username = _configValues["username"]?.value as? String
        let password = _configValues["password"]?.value as? String

        guard let username = username, let password = password else {
            Logger.httpPlugin.error("Username or password not set")
            throw NSError(
                domain: "HttpPlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "invalidCredentials")]
            )
        }

        if authManager.serverUrl != baseUrl {
            authManager.serverUrl = baseUrl
        }

        if authManager.username != username || !authManager.isPasswordSame(password: password) {
            try await authManager.login(username: username, password: password)
        }
    }

    // MARK: - Methods

    override func savePlugin() throws {
        Logger.httpPlugin.debug("Saving plugin: \(id)")
        guard let dbPool = DbService.shared.appDb else {
            throw NSError(
                domain: "HttpPlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "databaseNotAvailable")]
            )
        }

        // Create meta JSON
        let metaDict: [String: Any] = [
            "id": id,
            "name": name as Any,
            "version": version as Any,
            "description": description as Any,
            "authors": authors,
            "repository": repository as Any,
            "availableGenres": availableGenres.map { $0.rawValue },
            "authenticationEnabled": authenticationEnabled as Any,
            "editorEnabled": self is EditableHttpPlugin,
            "configs": configs.map { config in
                [
                    "key": config.key,
                    "name": config.name,
                    "description": config.description as Any,
                    "type": config.type.rawValue,
                    "defaultValue": config.defaultValue,
                    "options": config.options as Any,
                ]
            },
        ]

        let metaData = try JSONSerialization.data(withJSONObject: metaDict, options: [])
        guard let metaString = String(data: metaData, encoding: .utf8) else {
            throw NSError(
                domain: "HttpPlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "failedToEncodeMetaData")]
            )
        }

        // Create config values JSON
        let configValuesArray = _configValues.values.map { configValue in
            [
                "key": configValue.key,
                "value": configValue.value,
            ]
        }
        let configValuesData = try JSONSerialization.data(
            withJSONObject: configValuesArray, options: []
        )
        guard let configValuesString = String(data: configValuesData, encoding: .utf8) else {
            throw NSError(
                domain: "HttpPlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "failedToEncodeConfigValuesData")]
            )
        }

        // Save to database
        try dbPool.write { db in
            let httpPluginModel = HttpPluginModel(
                id: id,
                baseUrl: baseUrl,
                meta: metaString,
                configValues: configValuesString
            )
            try httpPluginModel.save(db)
        }
    }

    override func deletePlugin() throws {
        Logger.httpPlugin.debug("Deleting plugin: \(id)")
        guard let dbPool = DbService.shared.appDb else {
            throw NSError(
                domain: "HttpPlugin", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "databaseNotAvailable")]
            )
        }

        try dbPool.write { db in
            _ =
                try HttpPluginModel
                    .filter(Column("id") == id)
                    .deleteAll(db)
        }
    }

    override func isOnline() async throws -> Bool {
        try await setup()
        do {
            let (_, response) = try await authManager.get(path: "/")
            return response.statusCode == 200
        } catch {
            return false
        }
    }

    override func getSuggestions(_ query: String) async throws -> [String] {
        try await setup()
        let (data, _) = try await authManager.get(path: "/suggestion", query: ["query": query])
        return try JSONDecoder().decode([String].self, from: data)
    }

    override func search(_ query: String, page: UInt) async throws -> [Manga] {
        try await setup()
        let (data, _) = try await authManager.get(
            path: "/search", query: ["query": query, "page": String(page)]
        )
        return try JSONDecoder().decode([Manga].self, from: data)
    }

    override func getList(page: UInt, genre: Genre, status: Status) async throws -> [Manga] {
        try await setup()
        let (data, _) = try await authManager.get(
            path: "/manga",
            query: [
                "page": String(page),
                "genre": genre.rawValue,
                "status": String(status.rawValue),
            ]
        )
        return try JSONDecoder().decode([Manga].self, from: data)
    }

    override func getMangas(_ ids: [String]) async throws -> [Manga] {
        try await setup()
        let body = try JSONSerialization.data(withJSONObject: ids, options: [])
        let (data, _) = try await authManager.post(path: "/manga", body: body)
        return try JSONDecoder().decode([Manga].self, from: data)
    }

    override func getDetailedManga(_ id: String) async throws -> DetailedManga {
        try await setup()
        let (data, _) = try await authManager.get(path: "/manga/\(id)")
        return try JSONDecoder().decode(DetailedManga.self, from: data)
    }

    override func getChapter(manga: DetailedManga, chapter: Chapter) async throws -> [String] {
        try await setup()
        let (data, _) = try await authManager.get(path: "/manga/\(manga.id)/chapter/\(chapter.id)")
        return try JSONDecoder().decode([String].self, from: data)
    }

    override func getImage(_ url: String) async throws -> Data {
        try await setup()

        var path = url
        if path.lowercased().hasPrefix("http") {
            if path.hasPrefix(baseUrl) {
                path = String(path.dropFirst(baseUrl.count))
            } else {
                let (data, _) = try await URLSession.shared.data(from: URL(string: url)!)
                return data
            }
        }

        // Ensure path starts with / if baseUrl doesn't end with /
        if !baseUrl.hasSuffix("/") && !path.hasPrefix("/") {
            path = "/" + path
        }

        let (data, _) = try await authManager.get(path: path)
        return data
    }
}
