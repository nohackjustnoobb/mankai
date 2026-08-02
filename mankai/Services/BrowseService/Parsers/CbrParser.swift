//
//  CbrParser.swift
//  mankai
//
//  Created by Travis XU on 2/8/2026.
//

import Foundation
import UnrarKit

final class CbrParser: Parser {
    /// UnrarKit reads from a file URL, while `ParserFile` deliberately exposes
    /// backend-neutral data. This wrapper keeps the temporary file alive for as
    /// long as its archive can be used and removes it when the cache releases it.
    private final class CachedArchive {
        let archive: URKArchive
        let filenames: [String]
        let readLock = NSLock()
        private let fileURL: URL

        init(archive: URKArchive, filenames: [String], fileURL: URL) {
            self.archive = archive
            self.filenames = filenames
            self.fileURL = fileURL
        }

        deinit {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private var cachedArchiveKey: String?
    private var cachedArchive: CachedArchive?
    private let cacheLock = NSLock()

    private static let temporaryDirectory: URL = {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("cbr", isDirectory: true)

        if fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.removeItem(at: directory)
                Logger.cbrParser.debug("Cleared stale CBR temporary archives")
            } catch {
                // Cleanup must not prevent reading new archives. UUID filenames
                // keep new files from colliding with anything left behind.
                Logger.cbrParser.warning(
                    "Failed to clear stale CBR temporary archives: \(error)"
                )
            }
        }

        return directory
    }()

    override init() {
        super.init()
        // Accessing the static directory performs one process-wide stale-file sweep.
        _ = Self.temporaryDirectory
    }

    private func cachedArchive(for cacheKey: String) -> CachedArchive? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard cachedArchiveKey == cacheKey else { return nil }
        return cachedArchive
    }

    private func storeArchive(
        _ archive: CachedArchive,
        for cacheKey: String
    ) -> CachedArchive {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if cachedArchiveKey == cacheKey, let cachedArchive {
            return cachedArchive
        }

        cachedArchiveKey = cacheKey
        cachedArchive = archive
        return archive
    }

    private func archive(for file: ParserFile) async throws -> CachedArchive {
        if let cached = cachedArchive(for: file.cacheKey) {
            Logger.cbrParser.debug("Reusing cached archive: \(file.cacheKey)")
            return cached
        }

        Logger.cbrParser.debug("Loading archive content: \(file.cacheKey)")
        let data = try await file.getContent()
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: Self.temporaryDirectory,
            withIntermediateDirectories: true
        )
        let temporaryURL = Self.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("rar")

        do {
            try data.write(to: temporaryURL, options: .atomic)
            let archive = try URKArchive(url: temporaryURL)
            let filenames = try archive.listFilenames()
            return storeArchive(
                CachedArchive(
                    archive: archive,
                    filenames: filenames,
                    fileURL: temporaryURL
                ),
                for: file.cacheKey
            )
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func performRead<T>(
        cachedArchive: CachedArchive,
        body: (CachedArchive) throws -> T
    ) rethrows -> T {
        cachedArchive.readLock.lock()
        defer { cachedArchive.readLock.unlock() }
        return try body(cachedArchive)
    }

    private func withReadLock<T>(
        for file: ParserFile,
        body: (CachedArchive) throws -> T
    ) async throws -> T {
        Logger.cbrParser.debug("Acquiring read lock for: \(file.cacheKey)")
        let cachedArchive = try await archive(for: file)
        return try performRead(
            cachedArchive: cachedArchive,
            body: body
        )
    }

    override var id: String {
        "cbr"
    }

    override var supportedExtensions: [String] {
        ["cbr"]
    }

    override func parse(file: ParserFile) async throws -> DetailedManga {
        Logger.cbrParser.debug("Parsing archive: \(file.fileName)")

        var imagePaths: [String] = []
        var info: ComicInfo?
        var coverPath: String?
        try await withReadLock(for: file) { cachedArchive in
            let archive = cachedArchive.archive
            let filenames = cachedArchive.filenames
            imagePaths = Self.sortedImagePaths(in: filenames)

            guard !imagePaths.isEmpty else {
                Logger.cbrParser.error("No supported images found in archive: \(file.fileName)")
                throw MankaiErrorCode.browseArchiveNoImagesFoundInArchive.makeError()
            }

            if filenames.contains("ComicInfo.xml"),
               let infoData = try? archive.extractData(fromFile: "ComicInfo.xml")
            {
                Logger.cbrParser.debug("Found ComicInfo.xml, parsing metadata")
                info = ComicInfoParser.parse(data: infoData)
                if info == nil {
                    Logger.cbrParser.warning(
                        "ComicInfo.xml exists but could not be parsed, proceeding with image-only mode"
                    )
                }
            } else {
                Logger.cbrParser.debug(
                    "No ComicInfo.xml found, deferring filename metadata to presentation"
                )
            }

            coverPath = info?.frontCoverIndex.flatMap { index in
                guard index >= 0, index < imagePaths.count else { return nil }
                return imagePaths[index]
            } ?? imagePaths.first
        }

        Logger.cbrParser.debug("Parsed \(imagePaths.count) images")
        return ComicArchiveSupport.detailedManga(info: info, coverPath: coverPath)
    }

    override func prepareForPresentation(_ manga: DetailedManga, file: ParserFile) -> DetailedManga {
        ComicArchiveSupport.prepareForPresentation(manga, file: file)
    }

    override func parseChapter(
        manga: DetailedManga,
        chapter _: Chapter,
        file: ParserFile
    ) async throws -> [String] {
        Logger.cbrParser.debug("Parsing chapter images for manga: \(manga.id)")

        let imagePaths = try await withReadLock(for: file) { cachedArchive in
            Self.sortedImagePaths(in: cachedArchive.filenames)
        }

        Logger.cbrParser.debug("Found \(imagePaths.count) images for chapter of \(manga.id)")
        return imagePaths
    }

    override func parseImage(url: String, file: ParserFile) async throws -> Data {
        Logger.cbrParser.debug("Reading image: \(url)")

        return try await withReadLock(for: file) { cachedArchive in
            guard cachedArchive.filenames.contains(url) else {
                Logger.cbrParser.error("Entry not found in archive: \(url)")
                throw MankaiErrorCode.browseArchiveEntryNotFound.makeError()
            }
            return try cachedArchive.archive.extractData(fromFile: url)
        }
    }

    private static func sortedImagePaths(in filenames: [String]) -> [String] {
        filenames
            .filter(ComicArchiveSupport.isImagePath)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
