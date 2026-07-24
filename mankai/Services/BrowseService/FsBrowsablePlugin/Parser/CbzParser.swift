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
    private static var cachedArchivePath: String?
    private static var cachedArchive: Archive?
    private static let cacheLock = NSLock()

    /// `Archive` (ZIPFoundation) is not thread-safe: concurrent reads on the same instance can corrupt state.
    /// We serialize reads per *path* with a dedicated lock, so unrelated archives still run in parallel.
    private static var archiveReadLocks: [String: NSLock] = [:]
    private static let archiveReadLocksGuard = NSLock()

    /// Returns the per-archive lock for `path`, creating it on first use.
    private static func archiveReadLock(for path: String) -> NSLock {
        archiveReadLocksGuard.lock()
        defer { archiveReadLocksGuard.unlock() }
        if let lock = archiveReadLocks[path] {
            Logger.cbzParser.debug("Using existing read lock for: \(path)")
            return lock
        }
        Logger.cbzParser.debug("Creating new read lock for: \(path)")
        let lock = NSLock()
        archiveReadLocks[path] = lock
        return lock
    }

    /// Returns the `Archive` for `path`, reusing the cached instance on a path match.
    /// Opening a different path evicts the previous cached archive.
    private static func archive(for path: String) throws -> Archive {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = cachedArchive, cachedArchivePath == path {
            Logger.cbzParser.debug("Reusing cached archive: \(path)")
            return cached
        }

        Logger.cbzParser.debug("Opening new archive: \(path)")
        let archive = try Archive(url: URL(fileURLWithPath: path), accessMode: .read)
        cachedArchive = archive
        cachedArchivePath = path
        return archive
    }

    /// Resolves the (cached) `Archive` for `path` and runs `body` under the per-archive read lock.
    /// The path-keyed lock serializes only readers of the *same* archive.
    /// Readers on different archives proceed in parallel.
    /// An in-flight reader holds a valid `Archive` reference even if the cache entry is later evicted,
    /// and the path-keyed lock keeps concurrent readers of the same path consistent.
    private static func withReadLock<T>(
        for path: String,
        body: (Archive) throws -> T
    ) throws -> T {
        Logger.cbzParser.debug("Acquiring read lock for: \(path)")
        let lock = archiveReadLock(for: path)
        lock.lock()
        defer { lock.unlock() }
        let archive = try Self.archive(for: path)
        return try body(archive)
    }

    override init(baseURL: URL, pluginId: String) {
        super.init(baseURL: baseURL, pluginId: pluginId)

        Logger.cbzParser.debug("Initialized CbzParser for plugin: \(pluginId)")
    }

    override var id: String {
        "cbz"
    }

    override var supportedExtensions: [String] {
        ["cbz"]
    }

    override func getMangaId(path _: String, hash: String) -> String {
        hash
    }

    override func parse(path relativePath: String, hash: String) async throws -> DetailedManga {
        let path = resolveAbsolutePath(relativePath)
        Logger.cbzParser.debug("Parsing archive: \(path)")

        var imageEntries: [Entry] = []
        var info: ComicInfo? = nil
        var coverEntryPath: String? = nil
        try Self.withReadLock(for: path) { archive in
            imageEntries = archive
                .compactMap { entry -> Entry? in
                    guard entry.type == .file, Self.isImageEntry(entry) else { return nil }
                    return entry
                }
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

            guard !imageEntries.isEmpty else {
                Logger.cbzParser.error("No supported images found in archive: \(path)")
                throw NSError(
                    domain: "CbzParser", code: 0,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "noImagesFoundInArchive")]
                )
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
                Logger.cbzParser.debug("No ComicInfo.xml found, using filename and static chapter name")
            }

            let coverEntry = info?.frontCoverIndex.flatMap { idx -> Entry? in
                guard idx >= 0, idx < imageEntries.count else { return nil }
                return imageEntries[idx]
            } ?? imageEntries.first

            if let coverEntry {
                coverEntryPath = coverEntry.path
            }
        }

        Logger.cbzParser.debug("Parsed \(imageEntries.count) images, id: \(hash)")
        var manga = DetailedManga()
        manga.id = hash

        if let info {
            let series = info.series?.trimmingCharacters(in: .whitespacesAndNewlines)
            let titleField = info.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            // Manga title: prefer Series, fall back to the issue Title, then to the filename.
            if let series, !series.isEmpty {
                manga.title = series
            } else if let titleField, !titleField.isEmpty {
                manga.title = titleField
            } else {
                manga.title = (path as NSString).deletingPathExtension as String
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

            let chapter = Chapter(id: hash, title: chapterTitle)
            manga.chapters = ["volume": [chapter]]
            manga.latestChapter = chapter
        } else {
            // No ComicInfo.xml: use the filename as the title and a static chapter name.
            manga.title = (path as NSString).deletingPathExtension as String
            let chapter = Chapter(id: hash, title: manga.title)
            manga.chapters = ["volume": [chapter]]
            manga.latestChapter = chapter
        }

        // The cover is referenced as an entry inside the archive (`<archivePath>:<entryPath>`).
        // FsBrowsablePlugin fetches the bytes via `parseImage` and caches them to disk, so the parser only needs to point at the source entry here.
        if let coverEntryPath {
            manga.cover = "\(relativePath):\(coverEntryPath)"
        }

        return manga
    }

    override func parseChapter(manga: DetailedManga, chapter _: Chapter) async throws -> [String] {
        Logger.cbzParser.debug("Parsing chapter images for manga: \(manga.id)")
        guard let archivePath = manga.meta else {
            Logger.cbzParser.error("Missing archive path in manga meta")
            throw NSError(
                domain: "CbzParser", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "missingArchivePath")]
            )
        }
        let absoluteArchivePath = resolveAbsolutePath(archivePath)

        let imageEntries: [Entry] = try Self.withReadLock(for: absoluteArchivePath) { archive in
            archive
                .compactMap { entry -> Entry? in
                    guard entry.type == .file, Self.isImageEntry(entry) else { return nil }
                    return entry
                }
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }

        Logger.cbzParser.debug("Found \(imageEntries.count) images for chapter of \(manga.id)")
        return imageEntries.map { "\(archivePath):\($0.path)" }
    }

    override func parseImage(path: String) async throws -> Data {
        Logger.cbzParser.debug("Reading image: \(path)")
        // The path is encoded as `<archive_path>:<entry_path>`.
        guard let separator = path.range(of: ":") else {
            Logger.cbzParser.error("Invalid image path (missing ':' separator): \(path)")
            throw NSError(
                domain: "CbzParser", code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "invalidImagePath")]
            )
        }

        let archivePath = String(path[..<separator.lowerBound])
        let entryPath = String(path[separator.upperBound...])
        let absoluteArchivePath = resolveAbsolutePath(archivePath)

        return try Self.withReadLock(for: absoluteArchivePath) { archive in
            guard let entry = archive[entryPath] else {
                Logger.cbzParser.error("Entry not found in archive: \(entryPath)")
                throw NSError(
                    domain: "CbzParser", code: 0,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "entryNotFound")]
                )
            }

            return try Self.entryData(archive: archive, entry: entry)
        }
    }

    // MARK: - Helpers

    private func resolveAbsolutePath(_ path: String) -> String {
        URL(fileURLWithPath: path, relativeTo: baseURL)
            .absoluteURL.standardizedFileURL.path
    }

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
