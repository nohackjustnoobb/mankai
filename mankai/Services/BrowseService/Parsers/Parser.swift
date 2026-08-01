//
//  Parser.swift
//  mankai
//
//  Created by Travis XU on 14/7/2026.
//

import Foundation

/// A backend-neutral file supplied to a parser.
///
/// `cacheKey` must identify the current content. Callers should provide a new key
/// whenever the content changes so parsers can safely reuse derived state.
struct ParserFile {
    let cacheKey: String
    let fileName: String

    private let contentProvider: () async throws -> Data

    init(
        cacheKey: String,
        fileName: String,
        getContent: @escaping () async throws -> Data
    ) {
        self.cacheKey = cacheKey
        self.fileName = fileName
        contentProvider = getContent
    }

    func getContent() async throws -> Data {
        try await contentProvider()
    }
}

class Parser {
    /// The unique identifier for this parser.
    var id: String {
        fatalError("Not Implemented")
    }

    /// The file extensions supported by this parser.
    var supportedExtensions: [String] {
        fatalError("Not Implemented")
    }

    /// Parses the supplied file and returns a DetailedManga object.
    ///
    /// Note: The caller will override the `id` to "\(parserId)://\(hash):\(relativeURL)".
    /// Use `meta` to store additional metadata about the parsed manga.
    /// - Parameters:
    ///   - file: The backend-neutral manga file.
    /// - Returns: A DetailedManga object.
    /// - Throws: An error if the request fails.
    func parse(file _: ParserFile) async throws -> DetailedManga {
        fatalError("Not Implemented")
    }

    /// Applies file-dependent presentation metadata to a route-neutral cached manga.
    ///
    /// Parsers whose fallback metadata depends on the current filename can override
    /// this hook without storing that value in the shared cache.
    func prepareForPresentation(_ manga: DetailedManga, file _: ParserFile) -> DetailedManga {
        manga
    }

    /// Retrieves the list of image URLs for a specific chapter.
    /// - Parameters:
    ///   - manga: The manga containing the chapter.
    ///   - chapter: The chapter to retrieve images for.
    ///   - file: The backend-neutral manga file.
    /// - Returns: A list of image URLs.
    /// - Throws: An error if the request fails.
    func parseChapter(
        manga _: DetailedManga,
        chapter _: Chapter,
        file _: ParserFile
    ) async throws -> [String] {
        fatalError("Not Implemented")
    }

    /// Retrieves image data from a URL.
    /// - Parameters:
    ///   - url: The URL of the image.
    ///   - file: The backend-neutral manga file.
    /// - Returns: The image data.
    /// - Throws: An error if the request fails.
    func parseImage(url _: String, file _: ParserFile) async throws -> Data {
        fatalError("Not Implemented")
    }
}
