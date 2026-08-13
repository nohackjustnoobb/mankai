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
                coverUrl: manga.cover,
                plugin: plugin,
                tag: manga.status == .ended
                    ? String(localized: "ended")
                    : saved?.updates == true
                        ? String(localized: "updated")
                        : nil,
                tagColor: (saved?.updates == true ? .green.opacity(0.8) : .red.opacity(0.8))
            )
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .center) {
                // Title
                if let title = manga.title {
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                // Latest Chapter
                HStack(spacing: 4) {
                    if let record = record {
                        if let title = record.chapterTitle {
                            Text(title)
                        } else {
                            Text("chapter \(record.chapterId)")
                        }

                        Text("/")
                    } else if showNotRead {
                        Text("notRead")
                    }

                    if let latestChapter = manga.latestChapter, record != nil || !showNotRead {
                        if let title = latestChapter.title {
                            Text(title)

                        } else {
                            Text("chapter \(latestChapter.id)")
                        }
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}
