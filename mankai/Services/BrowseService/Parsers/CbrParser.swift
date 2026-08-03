//
//  CbrParser.swift
//  mankai
//
//  Created by Travis XU on 2/8/2026.
//

import Foundation
import UnrarKit

final class CbrParser: Parser {
    /// Couples each UnrarKit archive to its filenames and the lock that serializes reads.
    private final class CachedArchive {
        let archive: URKArchive
        let filenames: [String]
        let readLock = NSLock()

        init(archive: URKArchive, filenames: [String]) {
            self.archive = archive
            self.filenames = filenames
        }
    }

    private var cachedArchiveKey: String?
    private var cachedArchive: CachedArchive?
    private let cacheLock = NSLock()

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

        Logger.cbrParser.debug("Loading archive: \(file.cacheKey)")
        let url = try await file.getUrl()
        let archive = try URKArchive(url: url)
        let filenames = try archive.listFilenames()
        return storeArchive(
            CachedArchive(archive: archive, filenames: filenames),
            for: file.cacheKey
        )
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

        var manga = ComicArchiveSupport.detailedManga(info: info, coverPath: coverPath)
        if let chapter = manga.latestChapter {
            manga.meta = try ParserChapterMetadata(
                chapterId: chapter.id,
                pages: imagePaths
            ).encoded()
        }

        Logger.cbrParser.debug("Parsed \(imagePaths.count) images")
        return manga
    }

    override func prepareForPresentation(_ manga: DetailedManga, file: ParserFile) -> DetailedManga {
        ComicArchiveSupport.prepareForPresentation(manga, file: file)
    }

    override func parseChapter(
        manga: DetailedManga,
        chapter : Chapter,
        file: ParserFile
    ) async throws -> [String] {
        Logger.cbrParser.debug("Parsing chapter images for manga: \(manga.id)")

        if let pages = ParserChapterMetadata.decode(manga.meta)?.pages(for: chapter.id) {
            Logger.cbrParser.debug(
                "Using \(pages.count) cached page references for chapter: \(chapter.id)"
            )
            return pages
        }

        Logger.cbrParser.debug(
            "No compatible chapter metadata found; reparsing archive"
        )

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
