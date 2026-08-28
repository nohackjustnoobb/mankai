//
//  NfsParserFile.swift
//  mankai
//
//  Created by Travis XU on 28/8/2026.
//

import Foundation

/// A parser file that downloads and caches its NFS source on first access.
struct NfsParserFile: ParserFile {
    let cacheKey: String
    var fileName: String

    private let remotePath: String
    private let session: NfsSession
    private let temporaryDirectory: URL

    init(
        cacheKey: String,
        remotePath: String,
        fileName: String,
        session: NfsSession,
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
                Logger.nfsBrowsablePlugin.info("Downloading NFS parser file: \(remotePath)")
                try await session.download(path: remotePath, to: localURL)
                try Task.checkCancellation()
                Logger.nfsBrowsablePlugin.info("Downloaded NFS parser file: \(remotePath)")
            }
        } catch {
            Logger.nfsBrowsablePlugin.error(
                "Failed to download NFS parser file: \(remotePath)",
                error: error
            )
            throw error
        }
    }
}
