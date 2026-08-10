//
//  BrowsableFileUtilities.swift
//  mankai
//
//  Created by Travis XU on 10/8/2026.
//

import CryptoKit
import Foundation

/// Coordinates parser downloads that target the same local cache file.
actor ParserFileDownloadRegistry {
    static let shared = ParserFileDownloadRegistry()

    private var downloadTasks: [String: Task<URL, Error>] = [:]

    func file(
        at localURL: URL,
        download: @escaping @Sendable (URL) async throws -> Void
    ) async throws -> URL {
        let fileManager = FileManager.default
        let key = localURL.path(percentEncoded: false)

        if fileManager.fileExists(atPath: key) {
            Logger.browseService.debug("Parser cache hit: \(key)")
            return localURL
        }

        if let existingTask = downloadTasks[key] {
            Logger.browseService.debug("Waiting for parser download: \(key)")
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

enum BrowsableFileUtilities {
    static func parserCacheURL(for relativePath: String, in directory: URL) -> URL {
        let hash = SHA256.hash(data: Data(relativePath.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let extensionName = (relativePath as NSString).pathExtension
        let fileName = extensionName.isEmpty ? hash : "\(hash).\(extensionName)"
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }

    static func sha256(of fileURL: URL) throws -> String {
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

    static func uniqueFileName(for source: URL, existingNames: Set<String>) -> String {
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

    static func clearDirectoryIfPresent(at directory: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path(percentEncoded: false)) {
            try fileManager.removeItem(at: directory)
        }
    }
}
