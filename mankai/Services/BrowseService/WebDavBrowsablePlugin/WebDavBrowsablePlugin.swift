//
//  WebDavBrowsablePlugin.swift
//  mankai
//
//  Created by Travis XU on 10/8/2026.
//

import Foundation
import GRDB
import WebDAV

struct WebDavConnectionConfiguration {
    let baseURL: URL
    let username: String?
    let password: String?

    init(baseURL: String, username: String? = nil, password: String? = nil) throws {
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedURL),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            components.host?.isEmpty == false,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil
        else {
            throw MankaiErrorCode.browseWebDavInvalidConnectionConfiguration.makeError()
        }

        components.scheme = scheme
        if !components.percentEncodedPath.hasSuffix("/") {
            components.percentEncodedPath += "/"
        }
        guard let normalizedURL = components.url else {
            throw MankaiErrorCode.browseWebDavInvalidConnectionConfiguration.makeError()
        }

        self.baseURL = normalizedURL
        self.username = username.trimmed
        self.password = password.trimmed
    }
}

private struct MankaiWebDavAccount: WebDAVAccount {
    let username: String?
    let baseURL: String?
}

/// Serializes access to the callback-based WebDAV client.
actor WebDavSession {
    nonisolated let configuration: WebDavConnectionConfiguration

    private let client = WebDAV()
    private let account: MankaiWebDavAccount

    init(configuration: WebDavConnectionConfiguration) {
        self.configuration = configuration
        account = MankaiWebDavAccount(
            username: configuration.username ?? "",
            baseURL: configuration.baseURL.absoluteString
        )
    }

    func list(path: String) async throws -> [WebDAVFile] {
        try await withCheckedThrowingContinuation { continuation in
            client.listFiles(
                atPath: path,
                account: account,
                password: configuration.password ?? "",
                caching: .disableCache
            ) { files, error in
                if let error {
                    continuation.resume(throwing: Self.requestError(error))
                } else if let files {
                    continuation.resume(returning: files)
                } else {
                    continuation.resume(
                        throwing: MankaiErrorCode.browseWebDavRequestFailed.makeError())
                }
            }
        }
    }

    func downloadIfExists(path: String) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            client.download(
                fileAtPath: path,
                account: account,
                password: configuration.password ?? "",
                caching: .disableCache
            ) { data, error in
                if let error {
                    continuation.resume(throwing: Self.requestError(error))
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }

    func download(path: String) async throws -> Data {
        guard let data = try await downloadIfExists(path: path) else {
            throw MankaiErrorCode.browseFilesystemEntryNotFound.makeError()
        }
        return data
    }

    func createFolder(path: String) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            client.createFolder(
                atPath: path,
                account: account,
                password: configuration.password ?? ""
            ) { error in
                if let error {
                    continuation.resume(throwing: Self.requestError(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func upload(data: Data, path: String) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            client.upload(
                data: data,
                toPath: path,
                account: account,
                password: configuration.password ?? ""
            ) { error in
                if let error {
                    continuation.resume(throwing: Self.requestError(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func upload(file: URL, path: String) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            client.upload(
                file: file,
                toPath: path,
                account: account,
                password: configuration.password ?? ""
            ) { error in
                if let error {
                    continuation.resume(throwing: Self.requestError(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private nonisolated static func requestError(_ error: WebDAVError) -> Error {
        MankaiErrorCode.browseWebDavRequestFailed.makeError(underlyingError: error)
    }
}

final class WebDavBrowsablePlugin: GenericBrowsablePlugin, Importable {
    let configuration: WebDavConnectionConfiguration

    var importsEntity: Entity {
        Entity(
            path: "imports",
            displayName: "imports",
            name: "imports",
            type: .directory
        )
    }

    private let pluginName: String?
    private let _shouldSync: Bool
    private let session: WebDavSession
    private lazy var temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("webdav", isDirectory: true)
        .appendingPathComponent(id, isDirectory: true)

    /// Creates a new WebDAV plugin after validating the connection and resolving its identity.
    convenience init(session: WebDavSession, name: String?) async throws {
        do {
            let rootFiles = try await session.list(path: "")
            let identity: (id: String, shouldSync: Bool)

            if rootFiles.contains(where: { $0.fileName == ".mankai" }) {
                guard let data = try await session.downloadIfExists(path: ".mankai"),
                    let value = String(data: data, encoding: .utf8)
                else {
                    throw MankaiErrorCode.browseWebDavInvalidPlugin.makeError()
                }

                let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty else {
                    throw MankaiErrorCode.browseWebDavInvalidPlugin.makeError()
                }
                identity = (id: id, shouldSync: true)
            } else {
                let id = UUID().uuidString
                let data = Data(id.utf8)
                do {
                    try await session.upload(data: data, path: ".mankai")
                    identity = (id: id, shouldSync: true)
                } catch {
                    Logger.webDavBrowsablePlugin.warning(
                        "Failed to write .mankai for plugin \(id), using a local-only ID: \(error)"
                    )
                    identity = (id: id, shouldSync: false)
                }
            }

            try self.init(
                id: identity.id,
                name: name,
                configuration: session.configuration,
                session: session,
                shouldSync: identity.shouldSync
            )
        } catch {
            Logger.webDavBrowsablePlugin.error(
                "Failed to create WebDAV browsable plugin for \(session.configuration.baseURL.absoluteString)",
                error: error
            )
            throw error
        }
    }

    init(
        id: String,
        name: String?,
        configuration: WebDavConnectionConfiguration,
        session: WebDavSession? = nil,
        shouldSync: Bool = true
    ) throws {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        pluginName = trimmedName?.isEmpty == false ? trimmedName : nil
        _shouldSync = shouldSync
        self.configuration = configuration
        self.session = session ?? WebDavSession(configuration: configuration)

        try super.init(id: id)
        try BrowsableFileUtilities.clearDirectoryIfPresent(at: temporaryDirectory)
    }

    var baseURL: URL {
        configuration.baseURL
    }

    var username: String? {
        configuration.username
    }

    var password: String? {
        configuration.password
    }

    deinit {
        try? BrowsableFileUtilities.clearDirectoryIfPresent(at: temporaryDirectory)
    }

    override var name: String? {
        if let pluginName {
            return pluginName
        }

        let host = baseURL.host ?? baseURL.absoluteString
        let path = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? host : "\(host)/\(path)"
    }

    override var tags: [String] {
        ["WebDAV"]
    }

    override var systemImageName: String {
        "network"
    }

    override var canDownload: Bool {
        false
    }

    override var shouldSync: Bool {
        _shouldSync
    }

    static func loadPlugins() -> [WebDavBrowsablePlugin] {
        Logger.webDavBrowsablePlugin.debug("Loading WebDAV browsable plugins")
        guard let dbPool = DbService.shared.appDb else {
            Logger.webDavBrowsablePlugin.error("Database not available")
            return []
        }

        let models: [WebDavBrowsablePluginModel]
        do {
            models = try dbPool.read { db in
                try WebDavBrowsablePluginModel.fetchAll(db)
            }
        } catch {
            Logger.webDavBrowsablePlugin.error(
                "Failed to fetch WebDavBrowsablePluginModels",
                error: error
            )
            return []
        }

        var results: [WebDavBrowsablePlugin] = []
        for model in models {
            do {
                let configuration = try WebDavConnectionConfiguration(
                    baseURL: model.baseURL,
                    username: model.username,
                    password: model.password
                )
                try results.append(
                    WebDavBrowsablePlugin(
                        id: model.id,
                        name: model.name,
                        configuration: configuration,
                        shouldSync: model.shouldSync
                    ))
            } catch {
                Logger.webDavBrowsablePlugin.error(
                    "Failed to load WebDAV plugin \(model.id)",
                    error: error
                )
            }
        }
        return results
    }

    override func savePlugin() throws {
        Logger.webDavBrowsablePlugin.debug("Saving WebDAV plugin: \(id)")
        guard let db = DbService.shared.appDb else {
            throw MankaiErrorCode.browseFilesystemDatabaseNotAvailable.makeError()
        }

        let model = WebDavBrowsablePluginModel(
            id: id,
            name: pluginName,
            baseURL: baseURL.absoluteString,
            username: username,
            password: password,
            shouldSync: shouldSync
        )
        try db.write { db in
            try model.save(db)
        }
    }

    override func deletePlugin() throws {
        Logger.webDavBrowsablePlugin.debug("Deleting WebDAV plugin: \(id)")
        guard let db = DbService.shared.appDb else {
            throw MankaiErrorCode.browseFilesystemDatabaseNotAvailable.makeError()
        }

        _ = try db.write { db in
            try WebDavBrowsablePluginModel.deleteOne(db, key: id)
        }
        try super.deletePlugin()
        try BrowsableFileUtilities.clearDirectoryIfPresent(at: temporaryDirectory)
    }

    // MARK: - WebDAV backend hooks

    override func entries(path: String?) async throws -> [BrowsableEntry] {
        let remotePath = path ?? ""
        let files = try await session.list(path: remotePath)

        return files.compactMap { file in
            let fileName = file.fileName
            guard !fileName.isEmpty, !fileName.hasPrefix(".") else {
                return nil
            }

            let entryPath = remotePath.isEmpty ? fileName : "\(remotePath)/\(fileName)"
            return BrowsableEntry(
                path: entryPath,
                isDirectory: file.isDirectory,
                isRegularFile: !file.isDirectory
            )
        }
    }

    override func parserFile(relativePath: String, cacheKey: String) async throws -> ParserFile {
        WebDavParserFile(
            cacheKey: cacheKey,
            remotePath: relativePath,
            fileName: (relativePath as NSString).lastPathComponent,
            session: session,
            temporaryDirectory: temporaryDirectory
        )
    }

    override func hashFile(relativePath: String) async throws -> String {
        let file = try await parserFile(relativePath: relativePath, cacheKey: "hash")
        let fileURL = try await file.getUrl()
        return try BrowsableFileUtilities.sha256(of: fileURL)
    }

    override func isOnline() async throws -> Bool {
        do {
            _ = try await session.list(path: "")
            return true
        } catch {
            return false
        }
    }

    func importFile(from source: URL) async throws {
        let needsScopeAccess = source.startAccessingSecurityScopedResource()
        defer {
            if needsScopeAccess {
                source.stopAccessingSecurityScopedResource()
            }
        }

        let rootFiles = try await session.list(path: "")
        let importPath = importsEntity.path
        if !rootFiles.contains(where: { $0.fileName == importPath && $0.isDirectory }) {
            try await session.createFolder(path: importPath)
        }

        let existingFiles = try await session.list(path: importPath)
        let existingNames = Set(existingFiles.map(\.fileName))
        let fileName = BrowsableFileUtilities.uniqueFileName(
            for: source,
            existingNames: existingNames
        )
        try await session.upload(file: source, path: "\(importPath)/\(fileName)")
        try Task.checkCancellation()

        let importedFiles = try await session.list(path: importPath)
        guard importedFiles.contains(where: { $0.fileName == fileName && !$0.isDirectory }) else {
            throw MankaiErrorCode.browseWebDavRequestFailed.makeError()
        }
    }

}
