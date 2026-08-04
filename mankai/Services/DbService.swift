//
//  DbService.swift
//  mankai
//
//  Created by Travis XU on 26/6/2025.
//

import CoreData
import Foundation
import GRDB

final class DbService {
    /// The shared singleton instance of DbService.
    static let shared = DbService()

    private init() {
        Logger.dbService.debug("Initializing DbService")
    }

    /// The database pool for the main application database.
    lazy var appDb: DatabasePool? = {
        Logger.dbService.debug("Initializing appDb")
        guard
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first
        else {
            Logger.dbService.error("Could not find document directory")
            return nil
        }
        let fullUrl = documentsURL.appendingPathComponent("db.sqlite3")
        Logger.dbService.info("Database path: \(fullUrl.path(percentEncoded: false))")

        do {
            var config = Configuration()
            config.busyMode = .timeout(5.0)
            let dbPool = try DatabasePool(
                path: fullUrl.path(percentEncoded: false), configuration: config
            )

            try dbPool.write { db in
                try MangaModel.createTable(db)
                try SavedModel.createTable(db)
                try RecordModel.createTable(db)

                try JsPluginModel.createTable(db)
                try JsRuntimeKvPairModel.createTable(db)

                try HttpPluginModel.createTable(db)
                try FsPluginModel.createTable(db)
                try FsBrowsablePluginModel.createTable(db)
            }

            Logger.dbService.info("appDb initialized successfully")
            return dbPool
        } catch {
            Logger.dbService.error("Failed to initialize appDb", error: error)
            return nil
        }
    }()

    private var fsDb: [String: DatabasePool] = [:]

    /// Opens a file-system based database at the specified path.
    /// - Parameters:
    ///   - path: The file system path to the database.
    ///   - readOnly: Whether to open the database in read-only mode.
    /// - Returns: The `DatabasePool` if successful, otherwise `nil`.
    func openFsDb(_ path: String, readOnly: Bool) -> DatabasePool? {
        Logger.dbService.debug("Opening FsDb at \(path), readOnly: \(readOnly)")
        var config = Configuration()
        config.readonly = readOnly
        config.busyMode = .timeout(5.0)

        do {
            let pool = try DatabasePool(path: path, configuration: config)

            try pool.write { db in
                try FsMangaModel.createTable(db)
                try FsChapterGroupModel.createTable(db)
                try FsChapterModel.createTable(db)
                try FsImageModel.createTable(db)
            }

            fsDb[path] = pool
            Logger.dbService.info("FsDb opened successfully at \(path)")
            return pool
        } catch {
            Logger.dbService.error("Failed to open FsDb at \(path)", error: error)
            return nil
        }
    }

    private var downloadDb: DatabasePool?

    func openDownloadDb() -> DatabasePool? {
        if let db = downloadDb {
            return db
        }

        let path = DownloadPlugin.shared.downloadDir.appendingPathComponent("data.db").path(percentEncoded: false)

        Logger.dbService.debug("Opening DownloadDb at \(path)")
        var config = Configuration()
        config.busyMode = .timeout(5.0)

        do {
            let pool = try DatabasePool(path: path, configuration: config)

            try pool.write { db in
                try DownloadMangaModel.createTable(db)
                try DownloadChapterModel.createTable(db)
                try DownloadImageModel.createTable(db)
            }

            downloadDb = pool
            Logger.dbService.info("DownloadDb opened successfully at \(path)")
            return pool
        } catch {
            Logger.dbService.error("Failed to open DownloadDb at \(path)", error: error)
            return nil
        }
    }

    private var browsablePluginDb: DatabasePool?

    func openBrowsablePluginDb() -> DatabasePool? {
        if let db = browsablePluginDb {
            return db
        }

        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = cacheDir.appendingPathComponent(CacheDirectory.index).appendingPathComponent("browsableplugin")
        let path = dir.appendingPathComponent("data.db").path(percentEncoded: false)

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            Logger.dbService.error("Failed to create browsable plugin cache directory at \(dir.path(percentEncoded: false))", error: error)
            return nil
        }

        Logger.dbService.debug("Opening browsablePluginDb at \(path)")
        var config = Configuration()
        config.busyMode = .timeout(5.0)

        do {
            let pool = try DatabasePool(path: path, configuration: config)

            try pool.write { db in
                try BrowsablePluginMangaModel.createTable(db)
            }

            browsablePluginDb = pool
            Logger.dbService.info("browsablePluginDb opened successfully at \(path)")
            return pool
        } catch {
            Logger.dbService.error("Failed to open browsablePluginDb at \(path)", error: error)
            return nil
        }
    }

    func closeBrowsablePluginDb() {
        browsablePluginDb = nil
        Logger.dbService.debug("Closed browsablePluginDb pool")
    }
}
