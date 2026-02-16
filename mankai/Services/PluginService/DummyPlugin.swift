//
//  DummyPlugin.swift
//  mankai
//
//  Created by Travis XU on 16/2/2026.
//

import Foundation

class DummyPlugin: Plugin {
    private let _id: String

    override var id: String {
        _id
    }

    init(_ id: String) {
        _id = id
    }

    // DummyPlugin cannot be saved
    override func savePlugin() throws {}

    override func deletePlugin() throws {}

    override func isOnline() async throws -> Bool {
        throw NSError(domain: "DummyPlugin", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "dummyPluginCannotBeUsed")])
    }

    override func getSuggestions(_: String) async throws -> [String] {
        throw NSError(domain: "DummyPlugin", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "dummyPluginCannotBeUsed")])
    }

    override func search(_: String, page _: UInt) async throws -> [Manga] {
        throw NSError(domain: "DummyPlugin", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "dummyPluginCannotBeUsed")])
    }

    override func getList(page _: UInt, genre _: Genre, status _: Status) async throws -> [Manga] {
        throw NSError(domain: "DummyPlugin", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "dummyPluginCannotBeUsed")])
    }

    override func getMangas(_: [String]) async throws -> [Manga] {
        throw NSError(domain: "DummyPlugin", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "dummyPluginCannotBeUsed")])
    }

    override func getDetailedManga(_: String) async throws -> DetailedManga {
        throw NSError(domain: "DummyPlugin", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "dummyPluginCannotBeUsed")])
    }

    override func getChapter(manga _: DetailedManga, chapter _: Chapter) async throws -> [String] {
        throw NSError(domain: "DummyPlugin", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "dummyPluginCannotBeUsed")])
    }

    override func getImage(_: String) async throws -> Data {
        throw NSError(domain: "DummyPlugin", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "dummyPluginCannotBeUsed")])
    }
}
