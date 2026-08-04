//
//  SmbParserFile.swift
//  mankai
//
//  Created by Travis XU on 4/8/2026.
//

import CryptoKit
import Foundation

/// A parser file that downloads and caches its SMB source on first access.
struct SmbParserFile: ParserFile {
    /// Coordinates downloads shared by parser-file values for the same cache path.
    private actor DownloadRegistry {
        private var downloadTasks: [String: Task<URL, Error>] = [:]

        func file(
            at localURL: URL,
            download: @escaping @Sendable (URL) async throws -> Void
        ) async throws -> URL {
            let fileManager = FileManager.default
            let key = localURL.path(percentEncoded: false)

            if fileManager.fileExists(atPath: key) {
                Logger.smbBrowsablePlugin.debug(
                    "SMB parser cache hit: \(key)"
                )
                return localURL
            }

            if let existingTask = downloadTasks[key] {
                Logger.smbBrowsablePlugin.debug(
                    "Waiting for SMB parser download: \(key)"
                )
                return try await existingTask.value
            }

            try fileManager.createDirectory(
                at: localURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let task = Task<URL, Error> {
                do {
                    try await download(localURL)
                    return localURL
                } catch {
                    try? fileManager.removeItem(at: localURL)
                    throw error
                }
            }
            downloadTasks[key] = task

            do {
                let result = try await task.value
                downloadTasks.removeValue(forKey: key)
                return result
            } catch {
                downloadTasks.removeValue(forKey: key)
                throw error
            }
        }
    }

    private static let downloadRegistry = DownloadRegistry()

    let cacheKey: String
    var fileName: String

    private let remotePath: String
    private let session: SmbSession
    private let temporaryDirectory: URL

    init(
        cacheKey: String,
        remotePath: String,
        fileName: String,
        session: SmbSession,
        temporaryDirectory: URL
    ) {
        self.cacheKey = cacheKey
        self.remotePath = remotePath
        self.fileName = fileName
        self.session = session
        self.temporaryDirectory = temporaryDirectory
    }

    func getContent() async throws -> Data {
        let localURL = try await localURL()
        return try Data(contentsOf: localURL)
    }

    func getUrl() async throws -> URL {
        try await localURL()
    }

    private func localURL() async throws -> URL {
        let localURL = localURL(for: remotePath)
        do {
            return try await Self.downloadRegistry.file(at: localURL) { [session, remotePath] localURL in
                Logger.smbBrowsablePlugin.info(
                    "Downloading SMB parser file: \(remotePath)"
                )
                try await session.withConnectedConnection { connection in
                    try connection.downloadFile(remote: remotePath, local: localURL) {
                        completed, total, _, _ in
                        let progress = total > 0
                            ? Double(completed) / Double(total)
                            : 1
                        Logger.smbBrowsablePlugin.debug(
                            "Downloading \(remotePath): \(Int(progress * 100))%"
                        )
                        return !Task.isCancelled
                    }
                    try Task.checkCancellation()
                }

                Logger.smbBrowsablePlugin.info(
                    "Downloaded SMB parser file: \(remotePath)"
                )
            }
        } catch {
            Logger.smbBrowsablePlugin.error(
                "Failed to download SMB parser file: \(remotePath)",
                error: error
            )
            throw error
        }
    }

    private func localURL(for relativePath: String) -> URL {
        let hash = SHA256.hash(data: Data(relativePath.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let extensionName = (relativePath as NSString).pathExtension
        let fileName = extensionName.isEmpty ? hash : "\(hash).\(extensionName)"
        return temporaryDirectory.appendingPathComponent(fileName, isDirectory: false)
    }
}
