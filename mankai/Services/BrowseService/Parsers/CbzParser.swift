//
//  CbzParser.swift
//  mankai
//
//  Created by Travis Xu on 14/7/2026.
//

// This follows the RFC-CBZ specification by hyugogirubato (https://github.com/hyugogirubato/cbz/blob/main/docs/RFC-CBZ.md),
// which itself derives from the ComicInfo schema originally introduced by ComicRack and now governed by the anansi-project (https://github.com/anansi-project/comicinfo).
// Since this is an independent implementation, it may differ from the reference ComicRack/anansi-project implementation.
// Both referenced projects (RFC-CBZ and comicinfo) are released under the MIT License.

import Foundation
import ZIPFoundation

class CbzParser: Parser {
    /// Single-entry cache of the most recently opened `Archive`.
    /// Reopening the same CBZ would otherwise re-index it across the typical `parse` → `parseChapter` → `parseImage` sequence, so the last archive is kept in memory and reused on a cache-key match.
    private static var cachedArchiveKey: String?
    private static var cachedArchive: Archive?
    private static let cacheLock = NSLock()

    /// `Archive` (ZIPFoundation) is not thread-safe: concurrent reads on the same instance can corrupt state.
    /// We serialize reads per cache key with a dedicated lock, so unrelated archives still run in parallel.
    private static var archiveReadLocks: [String: NSLock] = [:]
    private static let archiveReadLocksGuard = NSLock()

    /// Returns the per-archive lock for `cacheKey`, creating it on first use.
    private static func archiveReadLock(for cacheKey: String) -> NSLock {
        archiveReadLocksGuard.lock()
        defer { archiveReadLocksGuard.unlock() }
        if let lock = archiveReadLocks[cacheKey] {
            Logger.cbzParser.debug("Using existing read lock for: \(cacheKey)")
            return lock
        }
        Logger.cbzParser.debug("Creating new read lock for: \(cacheKey)")
        let lock = NSLock()
        archiveReadLocks[cacheKey] = lock
        return lock
    }

    private static func cachedArchive(for cacheKey: String) -> Archive? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard cachedArchiveKey == cacheKey else { return nil }
        return cachedArchive
    }

    /// Stores `archive` unless another request populated the same key while its
    /// content was loading. Opening a different key evicts the previous archive.
    private static func storeArchive(_ archive: Archive, for cacheKey: String) -> Archive {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if cachedArchiveKey == cacheKey, let cachedArchive {
            return cachedArchive
        }

        cachedArchiveKey = cacheKey
        cachedArchive = archive
        return archive
    }

    /// Returns the `Archive` for `file`, loading its backend-neutral content only
    /// when the parser cache does not already contain `file.cacheKey`.
    private static func archive(for file: ParserFile) async throws -> Archive {
        if let cached = cachedArchive(for: file.cacheKey) {
            Logger.cbzParser.debug("Reusing cached archive: \(file.cacheKey)")
            return cached
        }

        Logger.cbzParser.debug("Loading archive content: \(file.cacheKey)")
        let data = try await file.getContent()
        let archive = try Archive(data: data, accessMode: .read)
        return storeArchive(archive, for: file.cacheKey)
    }

    /// Runs `body` under the per-archive read lock after asynchronously resolving
    /// the archive. Keeping the lock operation in a synchronous helper avoids
    /// suspending while an `NSLock` is held.
    private static func performRead<T>(
        archive: Archive,
        cacheKey: String,
        body: (Archive) throws -> T
    ) rethrows -> T {
        let lock = archiveReadLock(for: cacheKey)
        lock.lock()
        defer { lock.unlock() }
        return try body(archive)
    }

    /// Resolves the (cached) `Archive` for `file` and runs `body` under its read lock.
    /// The key-based lock serializes only readers of the *same* archive content.
    /// Readers on different archives proceed in parallel.
    /// An in-flight reader holds a valid `Archive` reference even if the cache entry is later evicted,
    /// and the key-based lock keeps concurrent readers of the same content consistent.
    private static func withReadLock<T>(
        for file: ParserFile,
        body: (Archive) throws -> T
    ) async throws -> T {
        Logger.cbzParser.debug("Acquiring read lock for: \(file.cacheKey)")
        let archive = try await archive(for: file)
        return try performRead(
            archive: archive,
            cacheKey: file.cacheKey,
            body: body
        )
    }

    override var id: String {
        "cbz"
    }

    override var supportedExtensions: [String] {
        ["cbz"]
    }

    override func parse(file: ParserFile) async throws -> DetailedManga {
        Logger.cbzParser.debug("Parsing archive: \(file.fileName)")

        var imageEntries: [Entry] = []
        var info: ComicInfo? = nil
        var coverEntryPath: String? = nil
        try await Self.withReadLock(for: file) { archive in
            imageEntries = archive
                .compactMap { entry -> Entry? in
                    guard entry.type == .file, Self.isImageEntry(entry) else { return nil }
                    return entry
                }
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

            guard !imageEntries.isEmpty else {
                Logger.cbzParser.error("No supported images found in archive: \(file.fileName)")
                throw MankaiErrorCode.browseArchiveNoImagesFoundInArchive.makeError()
            }

            if let infoEntry = archive["ComicInfo.xml"],
               let infoData = try? Self.entryData(archive: archive, entry: infoEntry)
            {
                Logger.cbzParser.debug("Found ComicInfo.xml, parsing metadata")
                info = ComicInfoParser.parse(data: infoData)
                if info == nil {
                    Logger.cbzParser.warning("ComicInfo.xml exists but could not be parsed, proceeding with image-only mode")
                }
            } else {
                Logger.cbzParser.debug(
                    "No ComicInfo.xml found, deferring filename metadata to presentation"
                )
            }

            let coverEntry = info?.frontCoverIndex.flatMap { idx -> Entry? in
                guard idx >= 0, idx < imageEntries.count else { return nil }
                return imageEntries[idx]
            } ?? imageEntries.first

            if let coverEntry {
                coverEntryPath = coverEntry.path
            }
        }

        Logger.cbzParser.debug("Parsed \(imageEntries.count) images")
        var manga = DetailedManga()

        if let info {
            let series = info.series?.trimmingCharacters(in: .whitespacesAndNewlines)
            let titleField = info.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            // Manga title: prefer Series, then the issue Title.
            if let series, !series.isEmpty {
                manga.title = series
            } else if let titleField, !titleField.isEmpty {
                manga.title = titleField
            }

            // Chapter title: the issue Title, or a static name if absent.
            let chapterTitle: String? = (titleField?.isEmpty == false) ? titleField : manga.title

            let summary = info.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
            manga.description = (summary?.isEmpty == false) ? summary : nil

            // Authors: aggregate the credit fields, which are comma-separated.
            let creditFields = [
                info.writer, info.penciller, info.inker, info.colorist,
                info.letterer, info.coverArtist, info.editor, info.translator,
            ]
            var authors: [String] = []
            for field in creditFields {
                guard let field, !field.isEmpty else { continue }
                authors.append(
                    contentsOf: field
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )
            }
            manga.authors = Self.uniqueStrings(authors)

            // Reading direction mapped from the <Manga> element.
            if let mangaTag = info.manga?.trimmingCharacters(in: .whitespacesAndNewlines),
               !mangaTag.isEmpty
            {
                switch mangaTag {
                case "No":
                    manga.readingDirection = .leftToRight
                case "Yes", "YesAndRightToLeft":
                    manga.readingDirection = .rightToLeft
                default:
                    break
                }
            }

            let chapter = Chapter(id: "0", title: chapterTitle)
            manga.chapters = [ChapterGroup(title: "volume", chapters: [chapter])]
            manga.latestChapter = chapter
        } else {
            let chapter = Chapter(id: "0", title: nil)
            manga.chapters = [ChapterGroup(title: "volume", chapters: [chapter])]
            manga.latestChapter = chapter
        }

        manga.cover = coverEntryPath

        return manga
    }

    override func prepareForPresentation(_ manga: DetailedManga, file: ParserFile) -> DetailedManga {
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
        manga: DetailedManga, chapter _: Chapter, file: ParserFile
    ) async throws -> [String] {
        Logger.cbzParser.debug("Parsing chapter images for manga: \(manga.id)")

        let imageEntries: [Entry] = try await Self.withReadLock(for: file) { archive in
            archive
                .compactMap { entry -> Entry? in
                    guard entry.type == .file, Self.isImageEntry(entry) else { return nil }
                    return entry
                }
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }

        Logger.cbzParser.debug("Found \(imageEntries.count) images for chapter of \(manga.id)")
        return imageEntries.map(\.path)
    }

    override func parseImage(url: String, file: ParserFile) async throws -> Data {
        Logger.cbzParser.debug("Reading image: \(url)")

        return try await Self.withReadLock(for: file) { archive in
            guard let entry = archive[url] else {
                Logger.cbzParser.error("Entry not found in archive: \(url)")
                throw MankaiErrorCode.browseArchiveEntryNotFound.makeError()
            }

            return try Self.entryData(archive: archive, entry: entry)
        }
    }

    // MARK: - Helpers

    /// Image extensions supported by the parser
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "webp", "tiff", "tif",
    ]

    private static func isImageEntry(_ entry: Entry) -> Bool {
        let name = (entry.path as NSString).lastPathComponent

        // Ignore hidden files and macOS metadata folders.
        if name.hasPrefix(".") || entry.path.contains("__MACOSX/") { return false }

        let ext = (name as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }

    private static func entryData(archive: Archive, entry: Entry) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry, consumer: { chunk in
            data.append(chunk)
        })
        return data
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

// MARK: - ComicInfo.xml parsing

private struct ComicInfo {
    var title: String?
    var series: String?
    var summary: String?
    var writer: String?
    var penciller: String?
    var inker: String?
    var colorist: String?
    var letterer: String?
    var coverArtist: String?
    var editor: String?
    var translator: String?
    var manga: String?
    /// Zero-based index of the FrontCover page in the sorted image list (if any).
    var frontCoverIndex: Int?
}

/// A lenient SAX parser for `ComicInfo.xml`. Only the elements relevant to this parser are collected.
private class ComicInfoParser: NSObject, XMLParserDelegate {
    private var info = ComicInfo()
    private var text = ""
    private var currentElement: String?
    private var inPages = false
    private var frontCoverIndex: Int?

    static func parse(data: Data) -> ComicInfo? {
        let parser = XMLParser(data: data)
        let delegate = ComicInfoParser()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else { return nil }
        var info = delegate.info
        info.frontCoverIndex = delegate.frontCoverIndex
        return info
    }

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        text = ""

        if elementName == "Pages" {
            inPages = true
            return
        }

        if inPages, elementName == "Page" {
            let type = attributeDict["Type"] ?? "Story"
            if type == "FrontCover", let image = attributeDict["Image"], let index = Int(image) {
                frontCoverIndex = index
            }
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if elementName == "Pages" {
            inPages = false
        } else if !inPages, let current = currentElement, elementName == current {
            switch current {
            case "Title":
                info.title = trimmed
            case "Series":
                info.series = trimmed
            case "Summary":
                info.summary = trimmed
            case "Writer":
                info.writer = trimmed
            case "Penciller":
                info.penciller = trimmed
            case "Inker":
                info.inker = trimmed
            case "Colorist":
                info.colorist = trimmed
            case "Letterer":
                info.letterer = trimmed
            case "CoverArtist":
                info.coverArtist = trimmed
            case "Editor":
                info.editor = trimmed
            case "Translator":
                info.translator = trimmed
            case "Manga":
                info.manga = trimmed
            default:
                break
            }
        }

        currentElement = nil
        text = ""
    }
}
