//
//  CbzParser.swift
//  mankai
//
//  Created by Travis XU on 14/7/2026.
//

import Foundation
import ZIPFoundation

final class CbzParser: Parser {
    /// Couples each ZIPFoundation archive to the lock that serializes its reads.
    /// Retaining this wrapper for an operation keeps an evicted archive alive until that operation has finished.
    nonisolated private final class CachedArchive: @unchecked Sendable {
        let archive: Archive
        let readLock = NSLock()

        init(archive: Archive) { self.archive = archive }
    }

    private var cachedArchiveKey: String?
    private var cachedArchive: CachedArchive?
    private let cacheLock = NSLock()
    private let archiveLoadRegistry = AsyncLoadRegistry<CachedArchive>()

    private func cachedArchive(for cacheKey: String) -> CachedArchive? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard cachedArchiveKey == cacheKey else { return nil }
        return cachedArchive
    }

    /// Stores `archive` unless another request populated the same key while its content was loading.
    /// Opening a different key evicts the previous archive.
    private func storeArchive(_ archive: CachedArchive, for cacheKey: String) -> CachedArchive {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if cachedArchiveKey == cacheKey, let cachedArchive { return cachedArchive }

        cachedArchiveKey = cacheKey
        cachedArchive = archive
        return archive
    }

    /// Returns the `Archive` for `file`, loading its backend-neutral content only when the parser cache does not already contain `file.cacheKey`.
    private func archive(for file: ParserFile) async throws -> CachedArchive {
        if let cached = cachedArchive(for: file.cacheKey) {
            Logger.cbzParser.debug("Reusing cached archive: \(file.cacheKey)")
            return cached
        }

        return try await archiveLoadRegistry.value(for: file.cacheKey) { @MainActor [self, file] in
            if let cached = cachedArchive(for: file.cacheKey) {
                Logger.cbzParser.debug("Reusing cached archive: \(file.cacheKey)")
                return cached
            }

            Logger.cbzParser.debug("Loading archive content: \(file.cacheKey)")
            let data = try await file.getContent()
            let loadedArchive =
                try await Task.detached(priority: .utility) {
                    let archive = try Archive(data: data, accessMode: .read)
                    return CachedArchive(archive: archive)
                }
                .value
            return storeArchive(loadedArchive, for: file.cacheKey)
        }
    }

    /// Keeping the lock operation in a synchronous helper avoids suspending while an `NSLock` is held.
    nonisolated private static func performRead<T>(
        cachedArchive: CachedArchive, body: @Sendable (Archive) throws -> T
    ) rethrows -> T {
        cachedArchive.readLock.lock()
        defer { cachedArchive.readLock.unlock() }
        return try body(cachedArchive.archive)
    }

    /// Resolves the (cached) `Archive` for `file` and runs `body` under its read lock.
    private func withReadLock<T: Sendable>(
        for file: ParserFile, body: @escaping @Sendable (Archive) throws -> T
    ) async throws -> T {
        Logger.cbzParser.debug("Acquiring read lock for: \(file.cacheKey)")
        let cachedArchive = try await archive(for: file)
        return
            try await Task.detached(priority: .utility) {
                try Self.performRead(cachedArchive: cachedArchive, body: body)
            }
            .value
    }

    override var id: String { "cbz" }

    override var supportedExtensions: [String] { ["cbz"] }

    override var supportedMimeTypes: [String] {
        ["application/vnd.comicbook+zip", "application/x-cbz"]
    }

    override func parse(file: ParserFile) async throws -> DetailedManga {
        Logger.cbzParser.debug("Parsing archive: \(file.fileName)")

        let fileName = file.fileName
        let parsed: (imagePaths: [String], info: ComicInfo?, coverPath: String?) =
            try await withReadLock(for: file) { archive in
                let imageEntries =
                    archive.compactMap { entry -> Entry? in
                        guard entry.type == .file, ComicArchiveSupport.isImagePath(entry.path)
                        else { return nil }
                        return entry
                    }
                    .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

                guard !imageEntries.isEmpty else {
                    Logger.cbzParser.error("No supported images found in archive: \(fileName)")
                    throw MankaiErrorCode.browseArchiveNoImagesFoundInArchive.makeError()
                }

                let info: ComicInfo?
                if let infoEntry = archive["ComicInfo.xml"],
                    let infoData = try? Self.entryData(archive: archive, entry: infoEntry)
                {
                    Logger.cbzParser.debug("Found ComicInfo.xml, parsing metadata")
                    info = ComicInfoParser.parse(data: infoData)
                    if info == nil {
                        Logger.cbzParser.warning(
                            "ComicInfo.xml exists but could not be parsed, proceeding with image-only mode"
                        )
                    }
                } else {
                    info = nil
                    Logger.cbzParser.debug(
                        "No ComicInfo.xml found, deferring filename metadata to presentation")
                }

                let coverEntry =
                    info?.frontCoverIndex
                    .flatMap { idx -> Entry? in
                        guard idx >= 0, idx < imageEntries.count else { return nil }
                        return imageEntries[idx]
                    } ?? imageEntries.first

                return (imageEntries.map(\.path), info, coverEntry?.path)
            }

        var manga = ComicArchiveSupport.detailedManga(
            info: parsed.info, coverPath: parsed.coverPath)
        if let chapter = manga.latestChapter {
            manga.meta = try ParserChapterMetadata(chapterId: chapter.id, pages: parsed.imagePaths)
                .encoded()
        }

        Logger.cbzParser.debug("Parsed \(parsed.imagePaths.count) images")
        return manga
    }

    override func prepareForPresentation(_ manga: DetailedManga, file: ParserFile) -> DetailedManga
    { ComicArchiveSupport.prepareForPresentation(manga, file: file) }

    override func parseChapter(manga: DetailedManga, chapter: Chapter, file: ParserFile)
        async throws -> [String]
    {
        Logger.cbzParser.debug("Parsing chapter images for manga: \(manga.id)")

        if let pages = ParserChapterMetadata.decode(manga.meta)?.pages(for: chapter.id) {
            Logger.cbzParser.debug(
                "Using \(pages.count) cached page references for chapter: \(chapter.id)")
            return pages
        }

        Logger.cbzParser.debug("No compatible chapter metadata found, reparsing archive")

        let imagePaths = try await withReadLock(for: file) { archive in
            archive.compactMap { entry -> String? in
                guard entry.type == .file, ComicArchiveSupport.isImagePath(entry.path) else {
                    return nil
                }
                return entry.path
            }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }

        Logger.cbzParser.debug("Found \(imagePaths.count) images for chapter of \(manga.id)")
        return imagePaths
    }

    override func parseImage(url: String, file: ParserFile) async throws -> Data {
        Logger.cbzParser.debug("Reading image: \(url)")

        return try await withReadLock(for: file) { archive in
            guard let entry = archive[url] else {
                Logger.cbzParser.error("Entry not found in archive: \(url)")
                throw MankaiErrorCode.browseArchiveEntryNotFound.makeError()
            }

            return try Self.entryData(archive: archive, entry: entry)
        }
    }

    // MARK: - Helpers

    nonisolated private static func entryData(archive: Archive, entry: Entry) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry, consumer: { chunk in data.append(chunk) })
        return data
    }
}
