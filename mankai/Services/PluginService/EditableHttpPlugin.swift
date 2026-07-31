//
//  EditableHttpPlugin.swift
//  mankai
//
//  Created by Travis XU on 11/2/2026.
//

import Foundation

class EditableHttpPlugin: HttpPlugin, Editable {
    override var tags: [String] {
        [String(localized: "http")]
    }

    // MARK: - Manga Management

    func upsertManga(_ manga: EditableManga) async throws -> String {
        try await setup()

        let jsonData = try JSONEncoder().encode(manga)
        let (data, _) = try await authManager.post(path: "/edit/manga", body: jsonData)

        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]

        await MainActor.run {
            objectWillChange.send()
        }

        return json?["id"] as? String ?? manga.id ?? ""
    }

    func deleteManga(_ mangaId: String) async throws {
        try await setup()
        _ = try await authManager.delete(path: "/edit/manga/\(mangaId)")

        await MainActor.run {
            objectWillChange.send()
        }
    }

    func upsertCover(mangaId: String, image: Data) async throws {
        try await setup()

        let contentType = image.detectImageMimeType()
        _ = try await authManager.request(
            method: "POST",
            path: "/edit/manga/\(mangaId)/cover",
            body: image,
            contentType: contentType
        )

        await MainActor.run {
            objectWillChange.send()
        }
    }

    // MARK: - Chapter Group Management

    func upsertChapterGroup(_ group: EditableChapterGroup) async throws {
        try await setup()

        guard group.mangaId != nil, group.title != nil else {
            throw MankaiErrorCode.pluginHttpMissingRequiredFields.makeError()
        }

        let jsonData = try JSONEncoder().encode(group)
        _ = try await authManager.post(path: "/edit/chapter-group", body: jsonData)

        await MainActor.run {
            objectWillChange.send()
        }
    }

    func deleteChapterGroup(id: String) async throws {
        try await setup()
        _ = try await authManager.delete(path: "/edit/chapter-group/\(id)")

        await MainActor.run {
            objectWillChange.send()
        }
    }

    func getChapterGroupId(mangaId: String, index: Int) async throws -> String? {
        try await setup()

        let (data, _) = try await authManager.get(
            path: "/edit/chapter-group/id",
            query: ["mangaId": mangaId, "index": String(index)]
        )

        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        return json?["id"] as? String
    }

    func getChapters(groupId: String) async throws -> [Chapter] {
        try await setup()

        let (data, _) = try await authManager.get(
            path: "/edit/chapter-group/\(groupId)/chapters"
        )

        return try JSONDecoder().decode([Chapter].self, from: data)
    }

    // MARK: - Chapter Management

    func upsertChapter(_ chapter: EditableChapter) async throws {
        try await setup()

        guard chapter.title != nil, chapter.chapterGroupId != nil else {
            throw MankaiErrorCode.pluginHttpMissingRequiredFields.makeError()
        }

        let jsonData = try JSONEncoder().encode(chapter)
        _ = try await authManager.post(path: "/edit/chapter", body: jsonData)

        await MainActor.run {
            objectWillChange.send()
        }
    }

    func deleteChapter(id: String) async throws {
        try await setup()
        _ = try await authManager.delete(path: "/edit/chapter/\(id)")

        await MainActor.run {
            objectWillChange.send()
        }
    }

    func arrangeChapterOrder(ids: [String]) async throws {
        try await setup()

        let jsonData = try JSONSerialization.data(withJSONObject: ids, options: [])
        _ = try await authManager.post(path: "/edit/chapter/order", body: jsonData)

        await MainActor.run {
            objectWillChange.send()
        }
    }

    func addImages(chapterId: String, images: [Data]) async throws {
        try await setup()

        let base64Images = images.map { $0.base64EncodedString() }
        let body: [String: Any] = ["images": base64Images]
        let jsonData = try JSONSerialization.data(withJSONObject: body, options: [])
        _ = try await authManager.post(
            path: "/edit/chapter/\(chapterId)/images",
            body: jsonData
        )

        await MainActor.run {
            objectWillChange.send()
        }
    }

    func deleteImages(ids: [String]) async throws {
        try await setup()

        let jsonData = try JSONSerialization.data(withJSONObject: ids, options: [])
        _ = try await authManager.post(path: "/edit/images/delete", body: jsonData)

        await MainActor.run {
            objectWillChange.send()
        }
    }

    func arrangeImageOrder(ids: [String]) async throws {
        try await setup()

        let jsonData = try JSONSerialization.data(withJSONObject: ids, options: [])
        _ = try await authManager.post(path: "/edit/images/order", body: jsonData)

        await MainActor.run {
            objectWillChange.send()
        }
    }
}
