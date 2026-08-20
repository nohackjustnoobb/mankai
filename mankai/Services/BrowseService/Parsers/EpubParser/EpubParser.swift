//
//  EpubParser.swift
//  mankai
//
//  Created by Travis XU on 3/8/2026.
//

import Foundation
import ZIPFoundation

final class EpubParser: Parser {
    private final class CachedArchive {
        let archive: Archive
        let readLock = NSLock()
        var publication: EpubPublication?

        init(archive: Archive) {
            self.archive = archive
        }
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
            Logger.epubParser.debug("Reusing cached EPUB archive: \(file.cacheKey)")
            return cached
        }

        return try await archiveLoadRegistry.value(for: file.cacheKey) { [self, file] in
            if let cached = cachedArchive(for: file.cacheKey) {
                Logger.epubParser.debug("Reusing cached EPUB archive: \(file.cacheKey)")
                return cached
            }

            Logger.epubParser.debug("Loading EPUB archive content: \(file.cacheKey)")
            let data = try await file.getContent()
            do {
                let archive = try Archive(data: data, accessMode: .read)
                return storeArchive(CachedArchive(archive: archive), for: file.cacheKey)
            } catch {
                Logger.epubParser.error("Invalid EPUB ZIP container", error: error)
                throw MankaiErrorCode.browseEpubInvalidContainer.makeError(
                    underlyingError: error
                )
            }
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
        let cachedArchive = try await archive(for: file)
        return try performRead(cachedArchive: cachedArchive, body: body)
    }

    override var id: String {
        "epub"
    }

    override var supportedExtensions: [String] {
        ["epub"]
    }

    override var supportedMimeTypes: [String] {
        ["application/epub+zip"]
    }

    override func parse(file: ParserFile) async throws -> DetailedManga {
        Logger.epubParser.debug("Parsing EPUB: \(file.fileName)")
        let publication = try await publication(for: file)

        var manga = DetailedManga()
        manga.title = publication.title
        manga.cover = publication.coverPath
        manga.description = publication.description
        manga.authors = publication.credits
        manga.genres = BrowsableMangaUtilities.genres(from: publication.subjects)
        manga.updatedAt = publication.modifiedAt
        manga.readingDirection = publication.readingDirection

        let chapter = Chapter(id: "0", title: publication.title)
        manga.chapters = [ChapterGroup(title: "volume", chapters: [chapter])]
        manga.latestChapter = chapter
        manga.meta = try ParserChapterMetadata(
            chapterId: chapter.id,
            pages: publication.pagePaths
        ).encoded()

        Logger.epubParser.debug("Parsed \(publication.pagePaths.count) EPUB image pages")
        return manga
    }

    override func prepareForPresentation(_ manga: DetailedManga, file: ParserFile) -> DetailedManga
    {
        guard manga.title == nil else { return manga }

        var presented = manga
        let filenameTitle = (file.fileName as NSString).deletingPathExtension
        presented.title = filenameTitle
        presented.chapters = presented.chapters.map { group in
            var presentedGroup = group
            presentedGroup.chapters = group.chapters.map { chapter in
                var presentedChapter = chapter
                if presentedChapter.title == nil {
                    presentedChapter.title = filenameTitle
                }
                return presentedChapter
            }
            return presentedGroup
        }

        if var latestChapter = presented.latestChapter,
            latestChapter.title == nil
        {
            latestChapter.title = filenameTitle
            presented.latestChapter = latestChapter
        }

        return presented
    }

    override func parseChapter(
        manga: DetailedManga,
        chapter: Chapter,
        file: ParserFile
    ) async throws -> [String] {
        Logger.epubParser.debug("Parsing EPUB chapter images for manga: \(manga.id)")

        if let pages = ParserChapterMetadata.decode(manga.meta)?.pages(for: chapter.id) {
            Logger.epubParser.debug(
                "Using \(pages.count) cached EPUB page references for chapter: \(chapter.id)"
            )
            return pages
        }

        Logger.epubParser.debug(
            "No compatible EPUB chapter metadata found, reparsing publication"
        )
        return try await publication(for: file).pagePaths
    }

    override func parseImage(url: String, file: ParserFile) async throws -> Data {
        Logger.epubParser.debug("Reading EPUB image: \(url)")

        return try await withReadLock(for: file) { cachedArchive in
            guard let entry = cachedArchive.archive[url], entry.type == .file else {
                Logger.epubParser.error("EPUB resource not found: \(url)")
                throw MankaiErrorCode.browseEpubResourceNotFound.makeError()
            }
            return try Self.entryData(archive: cachedArchive.archive, entry: entry)
        }
    }

    private func publication(for file: ParserFile) async throws -> EpubPublication {
        try await withReadLock(for: file) { cachedArchive in
            if let publication = cachedArchive.publication {
                return publication
            }

            do {
                let publication = try EpubPackageDecoder.decode(archive: cachedArchive.archive)
                cachedArchive.publication = publication
                return publication
            } catch let error as NSError
                where error.domain == MankaiErrorDomain.browseEpub.rawValue
            {
                Logger.epubParser.error("EPUB publication parsing failed", error: error)
                throw error
            } catch {
                Logger.epubParser.error("Failed to parse EPUB package", error: error)
                throw MankaiErrorCode.browseEpubInvalidPackage.makeError(
                    underlyingError: error
                )
            }
        }
    }

    private static func entryData(archive: Archive, entry: Entry) throws -> Data {
        var data = Data()
        _ = try archive.extract(
            entry,
            consumer: { chunk in
                data.append(chunk)
            })
        return data
    }
}
