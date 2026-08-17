//
//  ComicArchiveSupport.swift
//  mankai
//
//  Created by Travis XU on 2/8/2026.
//

import Foundation
import SWXMLHash

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
                    contentsOf:
                        field
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

/// A lenient parser for `ComicInfo.xml`. Only the elements relevant to the
/// comic archive parsers are collected.
final class ComicInfoParser {
    private var info = ComicInfo()
    private var frontCoverIndex: Int?

    static func parse(data: Data) -> ComicInfo? {
        let document = XMLHash.config { config in
            config.detectParsingErrors = true
        }.parse(data)
        guard !document.children.isEmpty else { return nil }

        let parser = ComicInfoParser()
        parser.visit(document, inPages: false)
        parser.info.frontCoverIndex = parser.frontCoverIndex
        return parser.info
    }

    private func visit(_ document: XMLIndexer, inPages: Bool) {
        for child in document.children {
            guard let element = child.element else { continue }
            let name = element.name

            if name == "Pages" {
                visit(child, inPages: true)
                continue
            }

            if inPages {
                if name == "Page",
                    element.attribute(by: "Type")?.text == "FrontCover",
                    let image = element.attribute(by: "Image")?.text,
                    let index = Int(image)
                {
                    frontCoverIndex = index
                }
                visit(child, inPages: true)
                continue
            }

            let text = element.recursiveText.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "Title":
                info.title = text
            case "Series":
                info.series = text
            case "Summary":
                info.summary = text
            case "Writer":
                info.writer = text
            case "Penciller":
                info.penciller = text
            case "Inker":
                info.inker = text
            case "Colorist":
                info.colorist = text
            case "Letterer":
                info.letterer = text
            case "CoverArtist":
                info.coverArtist = text
            case "Editor":
                info.editor = text
            case "Translator":
                info.translator = text
            case "Manga":
                info.manga = text
            default:
                visit(child, inPages: false)
            }
        }
    }
}
