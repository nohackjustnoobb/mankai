//
//  ReaderScreen.swift
//  mankai
//
//  Created by Travis XU on 7/2/2026.
//

import SwiftUI

struct ReaderScreen: View {
    let plugin: Plugin
    let manga: DetailedManga
    let downloadManga: DetailedManga?
    let chaptersKey: String
    let chapter: Chapter
    var initialPage: Int? = nil

    @AppStorage(SettingsKey.readerType.rawValue) private var readerTypeRawValue: Int =
        SettingsDefaults.readerType.rawValue

    @AppStorage(SettingsKey.respectMangaReadingDirection.rawValue) private var respectMangaReadingDirection: Bool =
        SettingsDefaults.respectMangaReadingDirection

    private var currentReaderType: ReaderType? {
        if respectMangaReadingDirection, let direction = manga.readingDirection, direction == .vertical {
            return .continuous
        }

        return ReaderType(rawValue: readerTypeRawValue)
    }

    var body: some View {
        Group {
            if let readerType = currentReaderType {
                switch readerType {
                case .continuous:
                    ContinuousReaderScreen(
                        plugin: plugin,
                        manga: manga,
                        downloadManga: downloadManga,
                        chaptersKey: chaptersKey,
                        chapter: chapter,
                        initialPage: initialPage
                    )
                case .paged:
                    PagedReaderScreen(
                        plugin: plugin,
                        manga: manga,
                        downloadManga: downloadManga,
                        chaptersKey: chaptersKey,
                        chapter: chapter,
                        initialPage: initialPage
                    )
                }
            }
        }
    }
}
