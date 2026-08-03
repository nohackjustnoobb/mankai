//
//  PdfParser.swift
//  mankai
//
//  Created by Travis XU on 2/8/2026.
//

import Foundation
import PDFKit
import UIKit

final class PdfParser: Parser {
    private final class CachedDocument {
        let document: PDFDocument
        let readLock = NSLock()

        init(document: PDFDocument) {
            self.document = document
        }
    }

    private var cachedDocumentKey: String?
    private var cachedDocument: CachedDocument?
    private let cacheLock = NSLock()

    private func cachedDocument(for cacheKey: String) -> CachedDocument? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard cachedDocumentKey == cacheKey else { return nil }
        return cachedDocument
    }

    private func storeDocument(
        _ document: CachedDocument,
        for cacheKey: String
    ) -> CachedDocument {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if cachedDocumentKey == cacheKey, let cachedDocument {
            return cachedDocument
        }

        cachedDocumentKey = cacheKey
        cachedDocument = document
        return document
    }

    private func document(for file: ParserFile) async throws -> CachedDocument {
        if let cached = cachedDocument(for: file.cacheKey) {
            Logger.pdfParser.debug("Reusing cached document: \(file.cacheKey)")
            return cached
        }

        Logger.pdfParser.debug("Loading document content: \(file.cacheKey)")
        let data = try await file.getContent()
        guard let document = PDFDocument(data: data) else {
            Logger.pdfParser.error("Invalid PDF document: \(file.fileName)")
            throw MankaiErrorCode.browsePdfInvalidDocument.makeError()
        }
        guard !document.isLocked else {
            Logger.pdfParser.error("Locked PDF document: \(file.fileName)")
            throw MankaiErrorCode.browsePdfPasswordProtectedDocument.makeError()
        }
        guard document.pageCount > 0 else {
            Logger.pdfParser.error("Empty PDF document: \(file.fileName)")
            throw MankaiErrorCode.browsePdfNoPagesFound.makeError()
        }

        return storeDocument(CachedDocument(document: document), for: file.cacheKey)
    }

    private func performRead<T>(
        cachedDocument: CachedDocument,
        body: (CachedDocument) throws -> T
    ) rethrows -> T {
        cachedDocument.readLock.lock()
        defer { cachedDocument.readLock.unlock() }
        return try body(cachedDocument)
    }

    private func withReadLock<T>(
        for file: ParserFile,
        body: (CachedDocument) throws -> T
    ) async throws -> T {
        Logger.pdfParser.debug("Acquiring read lock for: \(file.cacheKey)")
        let cachedDocument = try await document(for: file)
        return try performRead(
            cachedDocument: cachedDocument,
            body: body
        )
    }

    override var id: String {
        "pdf"
    }

    override var supportedExtensions: [String] {
        ["pdf"]
    }

    override func parse(file: ParserFile) async throws -> DetailedManga {
        Logger.pdfParser.debug("Parsing document: \(file.fileName)")

        let pageCount = try await withReadLock(for: file) { cachedDocument in
            cachedDocument.document.pageCount
        }

        var manga = DetailedManga()
        let chapter = Chapter(id: "0", title: nil)
        let pages = (0 ..< pageCount).map { Self.pageReference(for: $0) }
        manga.cover = Self.pageReference(for: 0)
        manga.chapters = [ChapterGroup(title: "volume", chapters: [chapter])]
        manga.latestChapter = chapter
        manga.meta = try ParserChapterMetadata(
            chapterId: chapter.id,
            pages: pages
        ).encoded()

        Logger.pdfParser.debug("Parsed \(pageCount) pages")
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
        manga: DetailedManga,
        chapter: Chapter,
        file: ParserFile
    ) async throws -> [String] {
        Logger.pdfParser.debug("Parsing chapter pages for manga: \(manga.id)")

        if let pages = ParserChapterMetadata.decode(manga.meta)?.pages(for: chapter.id) {
            Logger.pdfParser.debug(
                "Using \(pages.count) cached page references for chapter: \(chapter.id)"
            )
            return pages
        }

        Logger.pdfParser.debug(
            "No compatible chapter metadata found; reparsing document"
        )

        let pageCount = try await withReadLock(for: file) { cachedDocument in
            cachedDocument.document.pageCount
        }
        let pages = (0 ..< pageCount).map { Self.pageReference(for: $0) }

        Logger.pdfParser.debug("Found \(pages.count) pages for chapter of \(manga.id)")
        return pages
    }

    override func parseImage(url: String, file: ParserFile) async throws -> Data {
        Logger.pdfParser.debug("Rendering page: \(url)")

        let path = url as NSString
        guard path.pathExtension.lowercased() == "png",
              let pageIndex = Int(path.deletingPathExtension),
              pageIndex >= 0
        else {
            Logger.pdfParser.error("Invalid page reference: \(url)")
            throw MankaiErrorCode.browsePdfPageNotFound.makeError()
        }

        return try await withReadLock(for: file) { cachedDocument in
            let document = cachedDocument.document
            guard pageIndex < document.pageCount,
                  let page = document.page(at: pageIndex)
            else {
                Logger.pdfParser.error("Page not found: \(url)")
                throw MankaiErrorCode.browsePdfPageNotFound.makeError()
            }

            let bounds = page.bounds(for: .cropBox)
            guard bounds.width.isFinite,
                  bounds.height.isFinite,
                  bounds.width > 0,
                  bounds.height > 0
            else {
                Logger.pdfParser.error("Invalid bounds for page: \(url)")
                throw MankaiErrorCode.browsePdfFailedToRenderPage.makeError()
            }

            let isQuarterTurn = abs(page.rotation % 180) == 90
            let displaySize = isQuarterTurn
                ? CGSize(width: bounds.height, height: bounds.width)
                : bounds.size
            let image = page.thumbnail(of: displaySize, for: .cropBox)

            guard let data = image.pngData() else {
                Logger.pdfParser.error("Failed to encode page as PNG: \(url)")
                throw MankaiErrorCode.browsePdfFailedToRenderPage.makeError()
            }
            return data
        }
    }

    private static func pageReference(for index: Int) -> String {
        "\(index).png"
    }
}
