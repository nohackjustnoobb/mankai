//
//  NfsBrowsablePlugin.swift
//  mankai
//
//  Created by Travis XU on 28/8/2026.
//

import Foundation
import GRDB
import NFSKit

struct NfsConnectionConfiguration {
    let host: String
    let export: String

    init(host: String, export: String) throws {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExport = export.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let normalizedHost = Self.normalizedHost(trimmedHost),
            Self.serverURL(forNormalizedHost: normalizedHost) != nil,
            !trimmedExport.isEmpty,
            trimmedExport.hasPrefix("/"),
            !trimmedExport.contains("\\"),
            !trimmedExport.contains("\0")
        else {
            throw MankaiErrorCode.browseNfsInvalidConnectionConfiguration.makeError()
        }

        self.host = normalizedHost
        self.export = trimmedExport
    }

    var serverURL: URL {
        // Validation in the initializer guarantees this URL can be built.
        Self.serverURL(forNormalizedHost: host)!
    }

    static func serverURL(host: String) throws -> URL {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedHost = normalizedHost(trimmedHost),
            let url = serverURL(forNormalizedHost: normalizedHost)
        else {
            throw MankaiErrorCode.browseNfsInvalidConnectionConfiguration.makeError()
        }
        return url
    }

    private static func normalizedHost(_ host: String) -> String? {
        guard !host.isEmpty,
            host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
            !host.contains("/"),
            !host.contains("\\"),
            !host.contains("@")
        else {
            return nil
        }

        if host.hasPrefix("["), host.hasSuffix("]"), host.count > 2 {
            return String(host.dropFirst().dropLast())
        }
        return host
    }

    private static func serverURL(forNormalizedHost host: String) -> URL? {
        var components = URLComponents()
        components.scheme = "nfs"
        components.host = host
        guard let url = components.url, url.host?.isEmpty == false else {
            return nil
        }
        return url
    }
}

struct NfsEntry {
    let name: String
    let isDirectory: Bool
    let isRegularFile: Bool
}

/// Owns one mounted NFS client and remounts the export after a failed operation.
actor NfsSession {
    nonisolated let configuration: NfsConnectionConfiguration

    private var client: NFSClient?
    private var connectionTask: Task<Void, Error>?

    init(configuration: NfsConnectionConfiguration) {
        self.configuration = configuration
    }

    /// Returns the exports advertised by an NFS server.
    static func discoverExports(host: String) async throws -> [String] {
        let url = try NfsConnectionConfiguration.serverURL(host: host)
        guard let client = try NFSClient(url: url) else {
            throw MankaiErrorCode.browseNfsInvalidConnectionConfiguration.makeError()
        }

        let exports: [String] = try await withCheckedThrowingContinuation { continuation in
            client.listExports { result in
                continuation.resume(with: result)
            }
        }
        return Array(Set(exports.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty && $0.hasPrefix("/") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func disconnect() async {
        connectionTask?.cancel()
        connectionTask = nil

        guard let client else { return }
        self.client = nil
        await withCheckedContinuation { continuation in
            client.disconnect(export: configuration.export, gracefully: true) { _ in
                continuation.resume()
            }
        }
    }

    func list(path: String) async throws -> [NfsEntry] {
        let client = try await connectedClient()
        let nfsPath = path.isEmpty ? "/" : path

        do {
            let values: [[URLResourceKey: Any]] =
                try await withCheckedThrowingContinuation { continuation in
                    client.contentsOfDirectory(atPath: nfsPath) { result in
                        continuation.resume(with: result)
                    }
                }

            return values.compactMap { value in
                guard let name = value[.nameKey] as? String else { return nil }
                let type = value[.fileResourceTypeKey] as? URLFileResourceType
                return NfsEntry(
                    name: name,
                    isDirectory: type == .directory,
                    isRegularFile: type == .regular
                )
            }
        } catch {
            invalidate(client)
            throw error
        }
    }

    func downloadData(path: String) async throws -> Data {
        let client = try await connectedClient()
        do {
            return try await withCheckedThrowingContinuation { continuation in
                client.contents(atPath: path, progress: nil) { result in
                    continuation.resume(with: result)
                }
            }
        } catch {
            invalidate(client)
            throw error
        }
    }

    func download(path: String, to localURL: URL) async throws {
        let client = try await connectedClient()
        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                client.downloadItem(
                    atPath: path,
                    to: localURL,
                    progress: { completed, total in
                        let progress = total > 0 ? Double(completed) / Double(total) : 1
                        Logger.nfsBrowsablePlugin.debug(
                            "Downloading \(path): \(Int(progress * 100))%"
                        )
                        return true
                    }
                ) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            invalidate(client)
            throw error
        }
    }

    func createDirectory(path: String) async throws {
        let client = try await connectedClient()
        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                client.createDirectory(atPath: path) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            invalidate(client)
            throw error
        }
    }

    func upload(data: Data, path: String) async throws {
        let client = try await connectedClient()
        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                client.write(data: data, toPath: path, progress: { _ in true }) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            invalidate(client)
            throw error
        }
    }

    func upload(file: URL, path: String) async throws {
        let client = try await connectedClient()
        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                client.uploadItem(at: file, toPath: path, progress: { _ in true }) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            invalidate(client)
            throw error
        }
    }

    private func connectedClient() async throws -> NFSClient {
        if let client {
            return client
        }

        if let connectionTask {
            try await connectionTask.value
            guard let client else {
                throw MankaiErrorCode.browseNfsInvalidPlugin.makeError()
            }
            return client
        }

        let task = Task { [weak self] in
            guard let self else { return }
            try await self.openConnection()
        }
        connectionTask = task

        do {
            try await task.value
            connectionTask = nil
        } catch {
            connectionTask = nil
            throw error
        }

        guard let client else {
            throw MankaiErrorCode.browseNfsInvalidPlugin.makeError()
        }
        return client
    }

    private func openConnection() async throws {
        guard let client = try NFSClient(url: configuration.serverURL) else {
            throw MankaiErrorCode.browseNfsInvalidConnectionConfiguration.makeError()
        }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            client.connect(export: configuration.export) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        self.client = client
    }

    private func invalidate(_ failedClient: NFSClient) {
        if client === failedClient {
            client = nil
        }
    }
}

final class NfsBrowsablePlugin: GenericBrowsablePlugin, Importable {
    let configuration: NfsConnectionConfiguration

    var importsEntity: Entity {
        Entity(
            path: "imports",
            displayName: "imports",
            name: "imports",
            type: .directory
        )
    }

    private var session: NfsSession
    private var temporaryDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("nfs", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }

    /// Creates a new NFS plugin after mounting the export and resolving its identity.
    convenience init(session: NfsSession, name: String?) async throws {
        do {
            let rootEntries = try await session.list(path: "")
            let identity: (id: String, shouldSync: Bool)

            if rootEntries.contains(where: { $0.name == ".mankai" && $0.isRegularFile }) {
                let data = try await session.downloadData(path: ".mankai")
                guard let value = String(data: data, encoding: .utf8) else {
                    throw MankaiErrorCode.browseNfsInvalidPlugin.makeError()
                }

                let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty else {
                    throw MankaiErrorCode.browseNfsInvalidPlugin.makeError()
                }
                identity = (id: id, shouldSync: true)
            } else {
                let id = UUID().uuidString
                do {
                    try await session.upload(data: Data(id.utf8), path: ".mankai")
                    identity = (id: id, shouldSync: true)
                } catch {
                    Logger.nfsBrowsablePlugin.warning(
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
            Logger.nfsBrowsablePlugin.error(
                "Failed to create NFS browsable plugin for \(session.configuration.host)\(session.configuration.export)",
                error: error
            )
            await session.disconnect()
            throw error
        }
    }

    init(
        id: String,
        name: String?,
        configuration: NfsConnectionConfiguration,
        session: NfsSession? = nil,
        shouldSync: Bool = true
    ) throws {
        self.configuration = configuration
        self.session = session ?? NfsSession(configuration: configuration)

        try super.init(id: id, shouldSync: shouldSync)
        displayName = name.trimmed
        try BrowsableFileUtilities.clearDirectoryIfPresent(at: temporaryDirectory)
    }

    var host: String {
        configuration.host
    }

    var export: String {
        configuration.export
    }

    deinit {
        let session = session
        let temporaryDirectory = temporaryDirectory
        Task {
            await session.disconnect()
        }
        try? BrowsableFileUtilities.clearDirectoryIfPresent(at: temporaryDirectory)
    }

    override var name: String? {
        displayName ?? "\(host)\(export)"
    }

    override var tags: [String] {
        ["NFS"]
    }

    override var systemImageName: String {
        "network"
    }

    override var canDownload: Bool {
        false
    }

    static func loadPlugins() -> [NfsBrowsablePlugin] {
        Logger.nfsBrowsablePlugin.debug("Loading NFS browsable plugins")
        guard let dbPool = DbService.shared.appDb else {
            Logger.nfsBrowsablePlugin.error("Database not available")
            return []
        }

        let models: [NfsBrowsablePluginModel]
        do {
            models = try dbPool.read { db in
                try NfsBrowsablePluginModel.fetchAll(db)
            }
        } catch {
            Logger.nfsBrowsablePlugin.error(
                "Failed to fetch NfsBrowsablePluginModels",
                error: error
            )
            return []
        }

        var results: [NfsBrowsablePlugin] = []
        for model in models {
            do {
                let configuration = try NfsConnectionConfiguration(
                    host: model.host,
                    export: model.export
                )
                try results.append(
                    NfsBrowsablePlugin(
                        id: model.id,
                        name: model.name,
                        configuration: configuration,
                        shouldSync: model.shouldSync
                    ))
            } catch {
                Logger.nfsBrowsablePlugin.error(
                    "Failed to load NFS plugin \(model.id)",
                    error: error
                )
            }
        }
        return results
    }

    override func savePlugin() throws {
        Logger.nfsBrowsablePlugin.debug("Saving NFS plugin: \(id)")
        guard let db = DbService.shared.appDb else {
            throw MankaiErrorCode.browseFilesystemDatabaseNotAvailable.makeError()
        }

        let model = NfsBrowsablePluginModel(
            id: id,
            name: displayName,
            host: host,
            export: export,
            shouldSync: shouldSync
        )
        try db.write { db in
            try model.save(db)
        }
    }

    override func deletePlugin() throws {
        Logger.nfsBrowsablePlugin.debug("Deleting NFS plugin: \(id)")
        guard let db = DbService.shared.appDb else {
            throw MankaiErrorCode.browseFilesystemDatabaseNotAvailable.makeError()
        }

        _ = try db.write { db in
            try NfsBrowsablePluginModel.deleteOne(db, key: id)
        }
        try super.deletePlugin()
        try BrowsableFileUtilities.clearDirectoryIfPresent(at: temporaryDirectory)

        let session = session
        Task {
            await session.disconnect()
        }
    }

    // MARK: - NFS backend hooks

    override func entries(path: String?) async throws -> [BrowsableEntry] {
        let remotePath = path ?? ""
        let entries = try await session.list(path: remotePath)

        return entries.compactMap { entry in
            guard !entry.name.isEmpty, !entry.name.hasPrefix(".") else {
                return nil
            }

            let entryPath = remotePath.isEmpty ? entry.name : "\(remotePath)/\(entry.name)"
            return BrowsableEntry(
                path: entryPath,
                isDirectory: entry.isDirectory,
                isRegularFile: entry.isRegularFile
            )
        }
    }

    override func parserFile(relativePath: String, cacheKey: String) async throws -> ParserFile {
        NfsParserFile(
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

        let importPath = importsEntity.path
        let rootEntries = try await session.list(path: "")
        if !rootEntries.contains(where: { $0.name == importPath && $0.isDirectory }) {
            do {
                try await session.createDirectory(path: importPath)
            } catch {
                let refreshedEntries = try await session.list(path: "")
                guard
                    refreshedEntries.contains(where: {
                        $0.name == importPath && $0.isDirectory
                    })
                else {
                    throw error
                }
            }
        }

        let existingEntries = try await session.list(path: importPath)
        let existingNames = Set(existingEntries.map(\.name))
        let fileName = BrowsableFileUtilities.uniqueFileName(
            for: source,
            existingNames: existingNames
        )
        try await session.upload(file: source, path: "\(importPath)/\(fileName)")
        try Task.checkCancellation()

        let importedEntries = try await session.list(path: importPath)
        guard importedEntries.contains(where: { $0.name == fileName && $0.isRegularFile }) else {
            throw MankaiErrorCode.browseFilesystemEntryNotFound.makeError()
        }
    }
}
