//
//  DebugMangas.swift
//  mankai
//
//  Created by Travis XU on 26/6/2025.
//

import SwiftUI

extension DebugMangas {
    private func chapterText(_ chapter: Chapter?) -> String {
        guard let chapter = chapter else { return String(localized: "nil") }
        if let title = chapter.title {
            return "\(title) (\(String(localized: "id")): \(chapter.id))"
        } else {
            return "\(String(localized: "id")): \(chapter.id)"
        }
    }
}

struct DebugMangas: View {
    let mangas: [Manga]
    let plugin: JsPlugin
    var title: String? = nil

    var body: some View {
        Section(title ?? String(localized: "mangas")) {
            ForEach(mangas) { manga in
                NavigationLink(
                    destination: DebugGetMangasAndGetDetailedManga(
                        mangaId: manga.id, plugin: plugin
                    )
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("id")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(manga.id)
                                .font(.caption)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("status")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(manga.status.statusText)
                                .font(.caption)
                                .foregroundColor(.primary)
                        }

                        HStack {
                            Text("title").font(.caption)
                                .foregroundColor(.secondary)
                            Text(manga.title ?? String(localized: "nil"))
                                .font(.caption)
                                .foregroundColor(.primary)
                            Spacer()
                        }

                        HStack {
                            Text("cover")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(manga.cover ?? String(localized: "nil"))
                                .font(.caption)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                        }

                        HStack {
                            Text("latestChapter")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(chapterText(manga.latestChapter))
                                .font(.caption)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}
