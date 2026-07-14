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
    /// - Parameter path: The path to the manga file.
    /// - Returns: A DetailedManga object.
    /// - Throws: An error if the request fails.
    func parse(path _: String) async throws -> DetailedManga {
        fatalError("Not Implemented")
    }

    /// Retrieves the list of image URLs for a specific chapter.
    /// - Parameters:
    ///   - manga: The manga containing the chapter.
    ///   - chapter: The chapter to retrieve images for.
    /// - Returns: A list of image URLs.
    /// - Throws: An error if the request fails.
    func parseChapter(manga _: DetailedManga, chapter _: Chapter) async throws -> [String] {
        fatalError("Not Implemented")
    }

    /// Retrieves image data from a URL.
    /// - Parameter url: The URL of the image.
    /// - Returns: The image data.
    /// - Throws: An error if the request fails.
    func parseImage(path _: String) async throws -> Data {
        fatalError("Not Implemented")
    }
}
