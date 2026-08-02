//
//  ComicArchiveSupport.swift
//  mankai
//
//  Created by Travis XU on 2/8/2026.
//

import Foundation

enum ComicArchiveSupport {
    /// Image extensions supported as pages inside comic book archives.
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "webp", "tiff", "tif",
    ]

    static func isImagePath(_ path: String) -> Bool {
        let normalizedPath = path.replacingOccurrences(of: "\\", with: "/")
        let name = (normalizedPath as NSString).lastPathComponent

        // Ignore hidden files and macOS metadata folders.
        if name.hasPrefix(".") || normalizedPath.contains("__MACOSX/") { return false }

        let ext = (name as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }

    static func detailedManga(info: ComicInfo?, coverPath: String?) -> DetailedManga {
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

            // Chapter title: the issue Title, or the manga title if absent.
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
            manga.authors = uniqueStrings(authors)

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

        manga.cover = coverPath
        return manga
    }

    static func prepareForPresentation(
        _ manga: DetailedManga,
        file: ParserFile
    ) -> DetailedManga {
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

struct ComicInfo {
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

/// A lenient SAX parser for `ComicInfo.xml`. Only the elements relevant to the
/// comic archive parsers are collected.
final class ComicInfoParser: NSObject, XMLParserDelegate {
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
