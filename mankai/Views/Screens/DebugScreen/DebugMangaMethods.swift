//
//  DebugMangaMethods.swift
//  mankai
//
//  Created by Travis XU on 10/9/2026.
//

import SwiftUI

struct DebugMangaMethods: View {
    let manga: Manga
    let plugin: JsPlugin

    var body: some View {
        List {
            Section("methods") {
                NavigationLink(destination: DebugGetMangas(mangaIds: [manga.id], plugin: plugin)) {
                    Text("getMangas")
                }

                NavigationLink(
                    destination: DebugGetDetailedManga(mangaId: manga.id, plugin: plugin)
                ) { Text("getDetailedManga") }
            }
        }
        .navigationTitle(manga.title ?? manga.id).navigationBarTitleDisplayMode(.inline)
    }
}
