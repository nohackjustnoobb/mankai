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
    /// Reopening the same CBZ would otherwise re-index it across the typical `parse` → `parseChapter` → `parseImage` sequence, so the last archive is kept in memory and reused on a path match.
    private static var cachedArchiveURL: URL?
    private static var cachedArchive: Archive?
    private static let cacheLock = NSLock()

    /// `Archive` (ZIPFoundation) is not thread-safe: concurrent reads on the same instance can corrupt state.
    /// We serialize reads per *path* with a dedicated lock, so unrelated archives still run in parallel.
    private static var archiveReadLocks: [URL: NSLock] = [:]
    private static let archiveReadLocksGuard = NSLock()

    /// Returns the per-archive lock for `url`, creating it on first use.
    private static func archiveReadLock(for url: URL) -> NSLock {
        archiveReadLocksGuard.lock()
        defer { archiveReadLocksGuard.unlock() }
        if let lock = archiveReadLocks[url] {
            Logger.cbzParser.debug("Using existing read lock for: \(url.path)")
            return lock
        }
        Logger.cbzParser.debug("Creating new read lock for: \(url.path)")
        let lock = NSLock()
        archiveReadLocks[url] = lock
        return lock
    }

    /// Returns the `Archive` for `url`, reusing the cached instance on a URL match.
    /// Opening a different URL evicts the previous cached archive.
    private static func archive(for url: URL) throws -> Archive {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = cachedArchive, cachedArchiveURL == url {
            Logger.cbzParser.debug("Reusing cached archive: \(url.path)")
            return cached
        }

        Logger.cbzParser.debug("Opening new archive: \(url.path)")
        let archive = try Archive(url: url, accessMode: .read)
        cachedArchive = archive
        cachedArchiveURL = url
        return archive
    }

    /// Resolves the (cached) `Archive` for `url` and runs `body` under the per-archive read lock.
    /// The path-keyed lock serializes only readers of the *same* archive.
    /// Readers on different archives proceed in parallel.
    /// An in-flight reader holds a valid `Archive` reference even if the cache entry is later evicted,
    /// and the path-keyed lock keeps concurrent readers of the same path consistent.
    private static func withReadLock<T>(
        for url: URL,
        body: (Archive) throws -> T
    ) throws -> T {
        let standardizedURL = url.standardizedFileURL
        Logger.cbzParser.debug("Acquiring read lock for: \(standardizedURL.path)")
        let lock = archiveReadLock(for: standardizedURL)
        lock.lock()
        defer { lock.unlock() }
        let archive = try Self.archive(for: standardizedURL)
        return try body(archive)
    }

    override var id: String {
        "cbz"
    }

    override var supportedExtensions: [String] {
        ["cbz"]
    }

    override func parse(path: URL) async throws -> DetailedManga {
        let archiveURL = path.standardizedFileURL
        Logger.cbzParser.debug("Parsing archive: \(archiveURL.path)")

        var imageEntries: [Entry] = []
        var info: ComicInfo? = nil
        var coverEntryPath: String? = nil
        try Self.withReadLock(for: archiveURL) { archive in
            imageEntries = archive
                .compactMap { entry -> Entry? in
                    guard entry.type == .file, Self.isImageEntry(entry) else { return nil }
                    return entry
                }
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

            guard !imageEntries.isEmpty else {
                Logger.cbzParser.error("No supported images found in archive: \(archiveURL.path)")
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
            manga.chapters = ["volume": [chapter]]
            manga.latestChapter = chapter
        } else {
            let chapter = Chapter(id: "0", title: nil)
            manga.chapters = ["volume": [chapter]]
            manga.latestChapter = chapter
        }

        manga.cover = coverEntryPath

        return manga
    }

    override func prepareForPresentation(_ manga: DetailedManga, path: URL) -> DetailedManga {
        guard manga.title == nil else { return manga }

        var presented = manga
        let filenameTitle = path.deletingPathExtension().lastPathComponent
        presented.title = filenameTitle
        presented.chapters = presented.chapters.mapValues { chapters in
            chapters.map { chapter in
                var presentedChapter = chapter
                if presentedChapter.title == nil {
                    presentedChapter.title = filenameTitle
                }
                return presentedChapter
            }
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
        manga: DetailedManga, chapter _: Chapter, path: URL
    ) async throws -> [String] {
        Logger.cbzParser.debug("Parsing chapter images for manga: \(manga.id)")
        let archiveURL = path.standardizedFileURL

        let imageEntries: [Entry] = try Self.withReadLock(for: archiveURL) { archive in
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

    override func parseImage(url: String, path: URL) async throws -> Data {
        Logger.cbzParser.debug("Reading image: \(url)")
        let archiveURL = path.standardizedFileURL

        return try Self.withReadLock(for: archiveURL) { archive in
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
