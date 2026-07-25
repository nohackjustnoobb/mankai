//
//  Parser.swift
//  mankai
//
//  Created by Travis XU on 14/7/2026.
//

import Foundation

class Parser {
    /// The unique identifier for this parser.
    var id: String {
        fatalError("Not Implemented")
    }

    /// The file extensions supported by this parser.
    var supportedExtensions: [String] {
        fatalError("Not Implemented")
    }

    /// Parses the manga at the given path and returns a DetailedManga object.
    ///
    /// Note: The caller will override the `id` to "\(parserId)://\(hash):\(relativeURL)".
    /// Use `meta` to store additional metadata about the parsed manga.
    /// - Parameters:
    ///   - path: The path to the manga file.
    /// - Returns: A DetailedManga object.
    /// - Throws: An error if the request fails.
    func parse(path _: URL) async throws -> DetailedManga {
        fatalError("Not Implemented")
    }

    /// Applies path-dependent presentation metadata to a route-neutral cached manga.
    ///
    /// Parsers whose fallback metadata depends on the current filename can override
    /// this hook without storing that path-dependent value in the shared cache.
    func prepareForPresentation(_ manga: DetailedManga, path _: URL) -> DetailedManga {
        manga
    }

    /// Retrieves the list of image URLs for a specific chapter.
    /// - Parameters:
    ///   - manga: The manga containing the chapter.
    ///   - chapter: The chapter to retrieve images for.
    ///   - path: The path to the manga file.
    /// - Returns: A list of image URLs.
    /// - Throws: An error if the request fails.
    func parseChapter(manga _: DetailedManga, chapter _: Chapter, path _: URL) async throws -> [String] {
        fatalError("Not Implemented")
    }

    /// Retrieves image data from a URL.
    /// - Parameters:
    ///   - url: The URL of the image.
    ///   - path: The path to the manga file.
    /// - Returns: The image data.
    /// - Throws: An error if the request fails.
    func parseImage(url _: String, path _: URL) async throws -> Data {
        fatalError("Not Implemented")
    }
}
