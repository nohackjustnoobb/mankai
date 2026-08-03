//
//  Editable.swift
//  mankai
//
//  Created by Travis XU on 11/2/2026.
//

import Foundation

struct EditableManga: Codable {
    var id: String?
    var title: String?
    var status: Status?
    var description: String?
    var authors: [String]
    var genres: [Genre]
    var remarks: String?
}

struct EditableChapterGroup: Codable {
    var id: String?
    var title: String?
    var mangaId: String?
}

struct EditableChapter: Codable {
    var id: String?
    var title: String?
    var chapterGroupId: String?
}

protocol Editable: Plugin {
    // MARK: - Edit Manga

    /// Inserts or updates a manga entry.
    /// - Parameter manga: The detailed manga object to upsert.
    /// - Returns: The ID of the upserted manga.
    /// - Throws: An error if the operation fails.
    func upsertManga(_ manga: EditableManga) async throws -> String

    /// Deletes a manga by its ID.
    /// - Parameter mangaId: The ID of the manga to delete.
    /// - Throws: An error if the operation fails.
    func deleteManga(_ mangaId: String) async throws

    /// Inserts or updates the cover image for a manga.
    /// - Parameters:
    ///   - mangaId: The ID of the manga.
    ///   - image: The image data to set as the cover.
    /// - Throws: An error if the operation fails.
    func upsertCover(mangaId: String, image: Data) async throws

    // MARK: - Edit ChapterGroup

    /// Inserts or updates a chapter group.
    /// - Parameter group: The chapter group to upsert.
    /// - Throws: An error if the operation fails.
    func upsertChapterGroup(_ group: EditableChapterGroup) async throws

    /// Deletes a chapter group by its ID.
    /// - Parameter id: The ID of the chapter group to delete.
    /// - Throws: An error if the operation fails.
    func deleteChapterGroup(id: String) async throws

    /// Gets the chapters in a chapter group.
    /// - Parameter groupId: The ID of the chapter group.
    /// - Returns: An array of chapters in the group.
    /// - Throws: An error if the operation fails.
    func getChapters(groupId: String) async throws -> [Chapter]

    // MARK: - Edit Chapter

    /// Inserts or updates a chapter.
    /// - Parameter chapter: The chapter to upsert.
    /// - Throws: An error if the operation fails.
    func upsertChapter(_ chapter: EditableChapter) async throws

    /// Deletes a chapter by its ID.
    /// - Parameter id: The ID of the chapter to delete.
    /// - Throws: An error if the operation fails.
    func deleteChapter(id: String) async throws

    /// Arranges the order of chapters by their IDs.
    /// - Parameter ids: The ordered list of chapter IDs.
    /// - Throws: An error if the operation fails.
    func arrangeChapterOrder(ids: [String]) async throws

    /// Adds images to a chapter.
    /// - Parameters:
    ///   - chapterId: The ID of the chapter.
    ///   - images: The images to add.
    /// - Throws: An error if the operation fails.
    func addImages(chapterId: String, images: [Data]) async throws

    /// Deletes images by their IDs.
    /// - Parameter ids: The IDs of the images to delete.
    /// - Throws: An error if the operation fails.
    func deleteImages(ids: [String]) async throws

    /// Arranges the order of images by their IDs.
    /// - Parameter ids: The ordered list of image IDs.
    /// - Throws: An error if the operation fails.
    func arrangeImageOrder(ids: [String]) async throws
}
