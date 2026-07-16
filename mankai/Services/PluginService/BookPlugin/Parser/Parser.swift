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

    /// Returns the manga id for the file at `path`, given its content `hash`.
    ///
    /// The hash is computed by the caller (`BookPlugin`) so this is cheap and
    /// does not re-read the file. Each parser derives its own id scheme from
    /// the path and hash; for content-addressed formats the id is simply the
    /// hash. Used to look up the cache before triggering a full `parse`.
    /// - Parameters:
    ///   - path: The path to the manga file, relative to `baseURL`.
    ///   - hash: The content hash of the file, computed by the caller.
    /// - Returns: The manga id.
    func getMangaId(path _: String, hash _: String) -> String {
        fatalError("Not Implemented")
    }

    /// Parses the manga at the given path and returns a DetailedManga object.
    ///
    /// This performs the actual parse only: it does not hash the file, consult
    /// any cache, persist a cover to disk, or set the manga `meta`. The caller
    /// (`BookPlugin`) owns hashing, caching, and the `meta` path, and passes the
    /// content `hash` so the parser can use it as the manga id.
    /// - Parameters:
    ///   - path: The path to the manga file, relative to `baseURL`.
    ///     Implementations resolve it to an absolute URL via `absoluteURL`.
    ///   - hash: The content hash of the file, to use as the manga id.
    /// - Returns: A DetailedManga object.
    /// - Throws: An error if the request fails.
    func parse(path _: String, hash _: String) async throws -> DetailedManga {
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
