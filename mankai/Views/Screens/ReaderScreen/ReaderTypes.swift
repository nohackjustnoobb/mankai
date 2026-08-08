//
//  ReaderTypes.swift
//  mankai
//
//  Created by Travis XU on 7/8/2026.
//

import UIKit

struct ReaderRoute: Identifiable, Hashable {
    let plugin: Plugin
    let manga: DetailedManga
    let downloadManga: DetailedManga?
    let chapterGroupIndex: Int
    let chapter: Chapter
    let initialPage: Int?

    var id: String {
        "\(plugin.id):\(manga.id):\(chapterGroupIndex):\(chapter.id)"
    }

    static func == (lhs: ReaderRoute, rhs: ReaderRoute) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum ReaderLoadPhase: Equatable {
    case idle
    case loading
    case ready
    case failed
}

enum ReaderImageState {
    case loading
    case success(UIImage)
    case failed
}

struct ReaderGroup: Identifiable, Hashable {
    var id: [String] {
        urls
    }

    let urls: [String]

    func contains(_ url: String) -> Bool {
        urls.contains(url)
    }
}

enum ReaderStep {
    case previous
    case next
}

enum ReaderChapterAvailability: Equatable {
    case unavailable
    case locked
    case available
}

struct ReaderNavigationCommand: Equatable {
    let generation: Int
    let targetURL: String
    let animated: Bool
}

struct ReaderRenderState {
    let revision: Int
    let chapterID: String?
    let urls: [String]
    let images: [String: ReaderImageState]
    let groups: [ReaderGroup]
    let currentPage: Int
    let navigationCommand: ReaderNavigationCommand?
    let previousChapter: ReaderChapterAvailability
    let nextChapter: ReaderChapterAvailability
}

struct ReaderRenderConfiguration: Equatable {
    // Common
    let readingDirection: ReadingDirection
    let defaultGroupSize: Int

    /// Dependent
    let tapNavigation: Bool

    // Paged Reader
    let tapNavigationBehavior: TapBehavior
    let navigationOrientation: NavigationOrientation

    // Continuous Reader
    let snapToPage: Bool
    let softSnap: Bool
}

struct ReaderRenderActions {
    let pageDidChange: (Int) -> Void
    let requestGroupStep: (ReaderStep) -> Void
    let requestChapterStep: (ReaderStep) -> Void
    let toggleChrome: () -> Void
    let viewportDidChange: (CGSize) -> Void
}
