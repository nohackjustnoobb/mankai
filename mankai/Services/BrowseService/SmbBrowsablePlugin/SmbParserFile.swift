//
//  SmbParserFile.swift
//  mankai
//
//  Created by Travis XU on 4/8/2026.
//

import Foundation

/// A parser file that downloads and caches its SMB source on first access.
struct SmbParserFile: ParserFile {
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
        let localURL = BrowsableFileUtilities.parserCacheURL(
            for: remotePath,
            in: temporaryDirectory
        )
        do {
            return try await ParserFileDownloadRegistry.shared.file(at: localURL) {
                [session, remotePath] localURL in
                Logger.smbBrowsablePlugin.info(
                    "Downloading SMB parser file: \(remotePath)"
                )
                try await session.withConnectedConnection { connection in
                    try connection.downloadFile(remote: remotePath, local: localURL) {
                        completed, total, _, _ in
                        let progress =
                            total > 0
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
}
