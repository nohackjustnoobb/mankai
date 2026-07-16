//
//  Parser.swift
//  mankai
//
//  Created by Travis XU on 14/7/2026.
//

import Foundation

class Parser {
    /// The plugin root URL that relative paths passed to `parse` are resolved
    /// against. Kept on the parser so it can derive an absolute URL on its own.
    let baseURL: URL

    /// The id of the plugin that this parser belongs to.
    let pluginId: String

    init(baseURL: URL, pluginId: String) {
        self.baseURL = baseURL
        self.pluginId = pluginId
    }

    /// The unique identifier for this parser.
    var id: String {
        fatalError("Not Implemented")
    }

    /// The file extensions supported by this parser.
    var supportedExtensions: [String] {
        fatalError("Not Implemented")
    }

    /// Parses the manga at the given path and returns a DetailedManga object.
    /// - Parameter path: The path to the manga file, relative to `baseURL`.
    ///   Implementations resolve it to an absolute URL via `absoluteURL`.
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

    /// Retrieves a list of mangas from the given list of IDs.
    /// - Parameter ids: The list of manga IDs.
    /// - Returns: A list of Manga objects.
    /// - Throws: An error if the request fails.
    func getMangas(_: [String]) async throws -> [Manga] {
        fatalError("Not Implemented")
    }

    /// Retrieves a detailed manga from the given ID.
    /// - Parameter id: The manga ID.
    /// - Returns: A DetailedManga object.
    /// - Throws: An error if the request fails.
    func getDetailedManga(_: String) async throws -> DetailedManga {
        fatalError("Not Implemented")
    }
}
