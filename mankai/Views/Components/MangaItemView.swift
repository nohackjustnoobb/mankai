//
//  MangaItemView.swift
//  mankai
//
//  Created by Travis XU on 28/6/2025.
//

import SwiftUI

struct MangaItemView: View {
    let manga: Manga
    let plugin: Plugin
    var record: RecordModel? = nil
    var saved: SavedModel? = nil
    var showNotRead: Bool = false

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            // Cover Image
            MangaCoverView(
                coverUrl: manga.cover, plugin: plugin,
                tag: manga.status == .completed
                    ? String(localized: "mangaCompleted")
                    : saved?.updates == true ? String(localized: "new") : nil,
                tagColor: (saved?.updates == true ? .green : .red)
            )
            .aspectRatio(3 / 4, contentMode: .fit)

            VStack(alignment: .center) {
                // Title
                if let title = manga.title {
                    Text(title).font(.caption).foregroundColor(.primary).lineLimit(1)
                }

                // Latest Chapter
                HStack(spacing: 4) {
                    if let record = record {
                        if let title = record.chapterTitle {
                            Text(title)
                        } else {
                            Text(
                                String(format: String(localized: "chapterFormat"), record.chapterId)
                            )
                        }

                        Text("/")
                    } else if showNotRead {
                        Text("notRead")
                    }

                    if let latestChapter = manga.latestChapter, record != nil || !showNotRead {
                        if let title = latestChapter.title {
                            Text(title)

                        } else {
                            Text(
                                String(format: String(localized: "chapterFormat"), latestChapter.id)
                            )
                        }
                    }
                }
                .font(.caption2).foregroundColor(.secondary).foregroundStyle(.secondary)
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}
