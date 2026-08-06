//
//  SmbBrowsablePlugin.swift
//  mankai
//
//  Created by Travis XU on 4/8/2026.
//

import CryptoKit
import Foundation
import GRDB
import SwiftSMB

struct SmbConnectionConfiguration {
    let host: String
    let port: Int
    let share: String
    let username: String?
    let password: String?

    init(
        host: String,
        port: Int = 445,
        share: String,
        username: String? = nil,
        password: String? = nil
    ) throws {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedShare = share.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedHost.isEmpty else {
            throw MankaiErrorCode.browseSmbInvalidConnectionConfiguration.makeError()
        }
        guard (1 ... 65535).contains(port) else {
            throw MankaiErrorCode.browseSmbInvalidConnectionConfiguration.makeError()
        }
        guard !trimmedShare.isEmpty,
              !trimmedShare.contains("/"),
              !trimmedShare.contains("\\")
        else {
            throw MankaiErrorCode.browseSmbInvalidConnectionConfiguration.makeError()
        }

        self.host = trimmedHost
        self.port = port
        self.share = trimmedShare
        self.username = Self.optionalValue(username)
        self.password = Self.optionalValue(password)
    }

    private static func optionalValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var server: SMB.Server {
        SMB.Server(host: host, port: port)
    }

    var credentials: SMB.Credentials? {
        guard username != nil || password != nil else { return nil }
        return SMB.Credentials(user: username, password: password)
    }
}

/// Owns one authenticated SMB session and recreates it after a connection failure.
actor SmbSession {
    nonisolated let configuration: SmbConnectionConfiguration
    private var connection: SMB.Connection?
    private var connectionTask: Task<Void, Error>?

    init(configuration: SmbConnectionConfiguration) {
        self.configuration = configuration
    }

    /// Authenticates with an SMB server and returns its browsable disk shares.
    static func discoverShares(
        host: String,
        port: Int,
        username: String?,
        password: String?
    ) async throws -> [SMB.Share] {
        let configuration = try SmbConnectionConfiguration(
            host: host,
            port: port,
            share: "IPC$",
            username: username,
            password: password
        )

        return try SMB.listShares(
            server: configuration.server,
            credentials: configuration.credentials
        )
        .filter { !$0.name.isEmpty }
        .sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        invalidateConnection()
    }

    func withConnectedConnection<T>(
        _ operation: (SMB.Connection) throws -> T
    ) async throws -> T {
        try await ensureConnected()
        guard let connection else {
            throw MankaiErrorCode.browseFilesystemEntryNotFound.makeError()
        }

        do {
            return try operation(connection)
        } catch {
            invalidateConnection()
            throw error
        }
    }

    private func ensureConnected() async throws {
        if connection?.isConnected == true {
            return
        }

        if let connectionTask {
            try await connectionTask.value
            return
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
    }

    private func openConnection() async throws {
        connection = try SMB.connect(
            server: configuration.server,
            credentials: configuration.credentials,
            share: configuration.share
        )
    }

    private func invalidateConnection() {
        try? connection?.disconnect()
        connection = nil
    }
}

final class SmbBrowsablePlugin: GenericBrowsablePlugin {
    let configuration: SmbConnectionConfiguration

    private let pluginName: String?
    private let _shouldSync: Bool
    private let session: SmbSession
    private lazy var temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("smb", isDirectory: true)
        .appendingPathComponent(id, isDirectory: true)

    /// Creates a new SMB plugin using an existing session.
    convenience init(session: SmbSession, name: String?) async throws {
        do {
            let identity = try await session.withConnectedConnection { connection in
                if try connection.itemExists(at: ".mankai") == .file {
                    let data = try connection.loadFile(at: ".mankai")
                    guard let value = String(data: data, encoding: .utf8) else {
                        throw MankaiErrorCode.browseSmbInvalidPlugin.makeError()
                    }

                    let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !id.isEmpty else {
                        throw MankaiErrorCode.browseSmbInvalidPlugin.makeError()
                    }
                    return (id: id, shouldSync: true)
                }

                let id = UUID().uuidString
                do {
                    try connection.dumpToFile(Data(id.utf8), to: ".mankai")
                    return (id: id, shouldSync: true)
                } catch {
                    Logger.smbBrowsablePlugin.warning(
                        "Failed to write .mankai for plugin \(id); using a local-only ID: \(error)"
                    )
                    return (id: id, shouldSync: false)
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
            Logger.smbBrowsablePlugin.error(
                "Failed to create SMB browsable plugin for \(session.configuration.host):\(session.configuration.port)/\(session.configuration.share)",
                error: error
            )
            await session.disconnect()
            throw error
        }
    }

    init(
        id: String,
        name: String?,
        configuration: SmbConnectionConfiguration,
        session: SmbSession? = nil,
        shouldSync: Bool = true
    ) throws {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else {
            throw MankaiErrorCode.browseSmbInvalidPlugin.makeError()
        }

        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        pluginName = trimmedName?.isEmpty == false ? trimmedName : nil
        _shouldSync = shouldSync
        self.configuration = configuration
        self.session = session ?? SmbSession(configuration: configuration)

        super.init(id: trimmedId)
        try Self.clearTemporaryDirectory(at: temporaryDirectory)
    }

    var host: String {
        configuration.host
    }

    var port: Int {
        configuration.port
    }

    var share: String {
        configuration.share
    }

    var username: String? {
        configuration.username
    }

    var password: String? {
        configuration.password
    }

    deinit {
        let session = session
        let temporaryDirectory = temporaryDirectory
        Task {
            await session.disconnect()
        }
        try? Self.clearTemporaryDirectory(at: temporaryDirectory)
    }

    override var name: String? {
        pluginName ?? (port == 445 ? "\(host)/\(share)" : "\(host):\(port)/\(share)")
    }

    override var tags: [String] {
        ["SMB"]
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

    static func loadPlugins() -> [SmbBrowsablePlugin] {
        Logger.smbBrowsablePlugin.debug("Loading SMB browsable plugins")
        guard let dbPool = DbService.shared.appDb else {
            Logger.smbBrowsablePlugin.error("Database not available")
            return []
        }

        let models: [SmbBrowsablePluginModel]
        do {
            models = try dbPool.read { db in
                try SmbBrowsablePluginModel.fetchAll(db)
            }
        } catch {
            Logger.smbBrowsablePlugin.error(
                "Failed to fetch SmbBrowsablePluginModels",
                error: error
            )
            return []
        }

        var results: [SmbBrowsablePlugin] = []
        for model in models {
            do {
                let configuration = try SmbConnectionConfiguration(
                    host: model.host,
                    port: model.port,
                    share: model.share,
                    username: model.username,
                    password: model.password
                )
                try results.append(SmbBrowsablePlugin(
                    id: model.id,
                    name: model.name,
                    configuration: configuration,
                    shouldSync: model.shouldSync
                ))
            } catch {
                Logger.smbBrowsablePlugin.error(
                    "Failed to load SMB plugin \(model.id)",
                    error: error
                )
            }
        }
        return results
    }

    override func savePlugin() throws {
        Logger.smbBrowsablePlugin.debug("Saving SMB plugin: \(id)")
        guard let db = DbService.shared.appDb else {
            throw MankaiErrorCode.browseFilesystemDatabaseNotAvailable.makeError()
        }

        let model = SmbBrowsablePluginModel(
            id: id,
            name: pluginName,
            host: host,
            port: port,
            share: share,
            username: username,
            password: password,
            shouldSync: shouldSync
        )
        try db.write { db in
            try model.save(db)
        }
    }

    override func deletePlugin() throws {
        Logger.smbBrowsablePlugin.debug("Deleting SMB plugin: \(id)")
        guard let db = DbService.shared.appDb else {
            throw MankaiErrorCode.browseFilesystemDatabaseNotAvailable.makeError()
        }

        _ = try db.write { db in
            try SmbBrowsablePluginModel.deleteOne(db, key: id)
        }
        try super.deletePlugin()
        try Self.clearTemporaryDirectory(at: temporaryDirectory)

        let session = session
        Task {
            await session.disconnect()
        }
    }

    // MARK: - SMB backend hooks

    override func entries(path: String?) async throws -> [BrowsableEntry] {
        let remotePath = path ?? ""
        let entries = try await session.withConnectedConnection { connection in
            try connection.listDirectory(at: remotePath).map {
                (
                    name: $0.name,
                    isDirectory: $0.stat.type == .directory
                )
            }
        }

        return entries.compactMap { entry in
            guard !entry.name.hasPrefix(".") else {
                return nil
            }

            let entryPath = remotePath.isEmpty
                ? entry.name
                : "\(remotePath)/\(entry.name)"
            return BrowsableEntry(
                path: entryPath,
                isDirectory: entry.isDirectory,
                isRegularFile: !entry.isDirectory
            )
        }
    }

    override func parserFile(relativePath: String, cacheKey: String) async throws -> ParserFile {
        return SmbParserFile(
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
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            throw MankaiErrorCode.browseFilesystemUnableToOpenFileForHashing.makeError()
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1 << 16)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    override func isOnline() async throws -> Bool {
        do {
            _ = try await session.withConnectedConnection { connection in
                try connection.echo()
            }
            return true
        } catch {
            return false
        }
    }

    override func importFile(from source: URL) async throws {
        let importsPath = self.importsPath
        let needsScopeAccess = source.startAccessingSecurityScopedResource()
        defer {
            if needsScopeAccess {
                source.stopAccessingSecurityScopedResource()
            }
        }

        try await session.withConnectedConnection { connection in
            if try connection.itemExists(at: importsPath) != .directory {
                do {
                    try connection.makeDirectory(at: importsPath, makePath: true)
                } catch {
                    guard try connection.itemExists(at: importsPath) == .directory else {
                        throw error
                    }
                }
            }

            let existingEntries = try connection.listDirectory(at: importsPath)
            let existingNames = Set(existingEntries.map(\.name))
            let fileName = Self.uniqueFileName(for: source, existingNames: existingNames)
            let remotePath = "\(importsPath)/\(fileName)"
            try connection.uploadFile(local: source, remote: remotePath) { _, _, _, _ in
                !Task.isCancelled
            }
            try Task.checkCancellation()
        }
    }

    private static func uniqueFileName(for source: URL, existingNames: Set<String>) -> String {
        let baseName = source.lastPathComponent
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        let stem = (baseName as NSString).deletingPathExtension
        let extensionName = (baseName as NSString).pathExtension

        func candidate(_ suffix: String) -> String {
            let name = suffix.isEmpty ? stem : "\(stem) \(suffix)"
            return extensionName.isEmpty ? name : "\(name).\(extensionName)"
        }

        var result = candidate("")
        var counter = 1
        while existingNames.contains(result) {
            result = candidate("(\(counter))")
            counter += 1
        }
        return result
    }

    private static func clearTemporaryDirectory(at directory: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path(percentEncoded: false)) {
            try fileManager.removeItem(at: directory)
        }
    }
}
