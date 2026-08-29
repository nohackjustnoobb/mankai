//
//  BrowsableUtilities.swift
//  mankai
//
//  Created by Travis XU on 10/8/2026.
//

import CryptoKit
import Foundation
import SwiftUI

/// Coordinates parser downloads that target the same local cache file.
actor ParserFileDownloadRegistry {
    static let shared = ParserFileDownloadRegistry()

    private var downloadTasks: [String: Task<URL, Error>] = [:]

    func file(at localURL: URL, download: @escaping @Sendable (URL) async throws -> Void)
        async throws -> URL
    {
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
            at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)

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
    static func resolveIdentity<Session: BrowsableSession>(
        using session: Session, invalidPluginError: @autoclosure () -> Error
    ) async throws -> (id: String, shouldSync: Bool) {
        if let data = try await session.fileIfExists(path: ".mankai") {
            guard let value = String(data: data, encoding: .utf8) else {
                throw invalidPluginError()
            }

            let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { throw invalidPluginError() }
            return (id: id, shouldSync: true)
        }

        let id = UUID().uuidString
        do {
            try await session.upload(data: Data(id.utf8), path: ".mankai")
            return (id: id, shouldSync: true)
        } catch {
            Session.logger.warning(
                "Failed to write .mankai for plugin \(id), using a local-only ID: \(error)")
            return (id: id, shouldSync: false)
        }
    }

    static func parserCacheURL(for relativePath: String, in directory: URL) -> URL {
        let hash = SHA256.hash(data: Data(relativePath.utf8)).map { String(format: "%02x", $0) }
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
        let baseName = source.lastPathComponent.replacingOccurrences(of: "/", with: "_")
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

enum BrowsableMangaUtilities {
    static func genres(from values: [String]) -> [Genre] {
        var seen = Set<Genre>()
        var result: [Genre] = []

        for value in values {
            let normalizedValue = normalizedGenreName(value)
            guard
                let genre = Genre.allCases.first(where: {
                    $0 != .all && normalizedGenreName($0.rawValue) == normalizedValue
                }), seen.insert(genre).inserted
            else { continue }
            result.append(genre)
        }
        return result
    }

    private static func normalizedGenreName(_ value: String) -> String {
        value.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains)
            .map(String.init).joined()
    }
}

enum BrowsablePluginStyle {
    static let systemImagePalette: [Color] = [
        .red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .pink, .brown
    ]

    static func systemImageColor(for id: String) -> Color {
        var hash: UInt64 = 5381
        for byte in id.utf8 { hash = (hash &<< 5) &+ hash &+ UInt64(byte) }
        let index = Int(hash % UInt64(systemImagePalette.count))
        return systemImagePalette[index]
    }
}
