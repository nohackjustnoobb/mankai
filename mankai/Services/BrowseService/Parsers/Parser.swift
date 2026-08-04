//
//  Parser.swift
//  mankai
//
//  Created by Travis XU on 14/7/2026.
//

import Foundation

/// Page references discovered while parsing a file, persisted with the cached manga.
///
/// Keeping these references in `DetailedManga.meta` lets `parseChapter` avoid
/// inspecting the source file again.
struct ParserChapterMetadata: Codable {
    let chapters: [String: [String]]

    init(chapterId: String, pages: [String]) {
        chapters = [chapterId: pages]
    }

    func pages(for chapterId: String) -> [String]? {
        guard let pages = chapters[chapterId], !pages.isEmpty else { return nil }
        return pages
    }

    func encoded() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ value: String?) -> Self? {
        guard let value,
              let data = value.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

/// Coalesces concurrent asynchronous loads for the same parser cache key.
final class ParserLoadRegistry<Value>: @unchecked Sendable {
    private struct Entry {
        let id: UUID
        let task: Task<Value, Error>
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func value(
        for key: String,
        operation: @escaping () async throws -> Value
    ) async throws -> Value {
        let entry = lock.withLock {
            if let existing = entries[key] {
                return existing
            }

            let created = Entry(
                id: UUID(),
                task: Task {
                    try await operation()
                }
            )
            entries[key] = created
            return created
        }

        do {
            let result = try await entry.task.value
            removeEntry(for: key, id: entry.id)
            return result
        } catch {
            removeEntry(for: key, id: entry.id)
            throw error
        }
    }

    private func removeEntry(for key: String, id: UUID) {
        lock.withLock {
            guard entries[key]?.id == id else { return }
            entries.removeValue(forKey: key)
        }
    }
}

/// A backend-neutral file supplied to a parser.
///
/// `cacheKey` must identify the current content. Callers should provide a new key
/// whenever the content changes so parsers can safely reuse derived state.
protocol ParserFile {
    var cacheKey: String { get }
    var fileName: String { get }

    func getContent() async throws -> Data
    func getUrl() async throws -> URL
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
