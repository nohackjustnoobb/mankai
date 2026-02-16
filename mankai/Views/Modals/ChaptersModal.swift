//
//  ChaptersModal.swift
//  mankai
//
//  Created by Travis XU on 30/6/2025.
//

import SwiftUI

struct ChaptersModal: View {
    let plugin: Plugin
    let manga: DetailedManga
    let chaptersKey: String
    let record: RecordModel?
    let downloadChapters: Set<String>?
    let onNavigateToChapter: (Chapter, Int?, String?) -> Void

    private let chapters: [Chapter]

    init(
        plugin: Plugin, manga: DetailedManga, chaptersKey: String,
        record: RecordModel? = nil,
        downloadChapters: Set<String>? = nil,
        onNavigateToChapter: @escaping (Chapter, Int?, String?) -> Void
    ) {
        self.plugin = plugin
        self.manga = manga
        self.chaptersKey = chaptersKey
        self.record = record
        self.downloadChapters = downloadChapters
        self.onNavigateToChapter = onNavigateToChapter
        chapters = manga.chapters[chaptersKey] ?? []
    }

    @Environment(\.dismiss) var dismiss
    @State private var isReversed = true

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        if chapters.isEmpty {
                            Text("noChaptersAvailable")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(isReversed ? chapters.reversed() : chapters, id: \.id) { chapter in
                                Button(action: {
                                    onNavigateToChapter(chapter, nil, chaptersKey)
                                }) {
                                    HStack {
                                        Text(chapter.title ?? chapter.id)
                                            .foregroundColor(.primary)

                                        if let downloadChapters = downloadChapters,
                                           downloadChapters.contains(chapter.id)
                                        {
                                            Image(systemName: "network.slash")
                                                .foregroundColor(.secondary)
                                        }

                                        if let record = record, record.chapterId == chapter.id {
                                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                                .foregroundColor(.accentColor)
                                        }

                                        Spacer()
                                        Image(systemName: (chapter.locked ?? false) ? "lock.fill" : "chevron.right")
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .disabled(chapter.locked ?? false)
                            }
                        }
                    } header: {
                        Spacer(minLength: 0)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle(LocalizedStringKey(chaptersKey))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack {
                            Button(action: {
                                isReversed.toggle()
                            }) {
                                Image(
                                    systemName: isReversed
                                        ? "arrow.up"
                                        : "arrow.down")
                            }

                            if plugin is Editable {
                                NavigationLink(destination: {
                                    UpdateChaptersModal(
                                        plugin: plugin as! any Editable, manga: manga, chaptersKey: chaptersKey
                                    )
                                }) {
                                    Image(systemName: "pencil")
                                }
                            }
                        }
                    }

                    ToolbarItem(placement: .principal) {
                        VStack {
                            Text(LocalizedStringKey(chaptersKey))
                                .font(.headline)
                            Text("\(chapters.count) chapters")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("close") {
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    if let record = record {
                        proxy.scrollTo(record.chapterId, anchor: .center)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}
