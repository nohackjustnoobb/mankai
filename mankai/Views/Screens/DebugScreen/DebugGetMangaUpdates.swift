//
//  DebugGetMangaUpdates.swift
//  mankai
//
//  Created by Travis XU on 10/9/2026.
//

import SwiftUI

struct DebugGetMangaUpdates: View {
    let manga: DetailedManga
    let plugin: JsPlugin

    @State var mangas: [Manga]? = nil

    var body: some View {
        Group {
            if !plugin.supports(.mangaUpdates) {
                DebugMethodNotSupported()
            } else if manga.latestChapter == nil {
                ContentUnavailableView {
                    Label {
                        Text("latestChapterRequired")
                    } icon: {
                        Image(systemName: "books.vertical")
                    }
                } description: {
                    Text("latestChapterRequiredDescription")
                }
            } else if let mangas = mangas {
                List { DebugMangas(mangas: mangas, plugin: plugin, showsMethodPicker: false) }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard plugin.supports(.mangaUpdates), let latestChapter = manga.latestChapter else {
                return
            }
            mangas = try! await plugin.getMangaUpdates([
                MangaUpdateRequest(id: manga.id, latestChapter: latestChapter)
            ])
            Logger.jsPlugin.debug("mangas: \(mangas as Any)")
        }
        .navigationTitle("getMangaUpdates")
    }
}
