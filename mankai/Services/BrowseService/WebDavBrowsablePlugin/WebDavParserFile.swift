//
//  WebDavParserFile.swift
//  mankai
//
//  Created by Travis XU on 10/8/2026.
//

import Foundation

/// A parser file that downloads and caches its WebDAV source on first access.
struct WebDavParserFile: ParserFile {
    let cacheKey: String
    var fileName: String

    private let remotePath: String
    private let session: WebDavSession
    private let temporaryDirectory: URL

    init(
        cacheKey: String,
        remotePath: String,
        fileName: String,
        session: WebDavSession,
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
                Logger.webDavBrowsablePlugin.info("Downloading WebDAV parser file: \(remotePath)")
                let data = try await session.download(path: remotePath)
                try Task.checkCancellation()
                try data.write(to: localURL, options: .atomic)
                Logger.webDavBrowsablePlugin.info("Downloaded WebDAV parser file: \(remotePath)")
            }
        } catch {
            Logger.webDavBrowsablePlugin.error(
                "Failed to download WebDAV parser file: \(remotePath)",
                error: error
            )
            throw error
        }
    }
}
