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
    let chapterGroupIndex: Int
    let record: RecordModel?
    let downloadChapters: Set<String>?
    let allowEditing: Bool
    let onNavigateToChapter: (Chapter, Int?, Int?) -> Void

    private let chapterGroupTitle: String
    private let chapters: [Chapter]

    init(
        plugin: Plugin, manga: DetailedManga, chapterGroupIndex: Int,
        record: RecordModel? = nil,
        downloadChapters: Set<String>? = nil,
        allowEditing: Bool = true,
        onNavigateToChapter: @escaping (Chapter, Int?, Int?) -> Void
    ) {
        self.plugin = plugin
        self.manga = manga
        self.chapterGroupIndex = chapterGroupIndex
        self.record = record
        self.downloadChapters = downloadChapters
        self.allowEditing = allowEditing
        self.onNavigateToChapter = onNavigateToChapter

        if manga.chapters.indices.contains(chapterGroupIndex) {
            let chapterGroup = manga.chapters[chapterGroupIndex]
            chapterGroupTitle = chapterGroup.title
            chapters = chapterGroup.chapters
        } else {
            chapterGroupTitle = ""
            chapters = []
        }
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
                            ForEach(isReversed ? chapters.reversed() : chapters, id: \.id) {
                                chapter in
                                Button(action: {
                                    onNavigateToChapter(chapter, nil, chapterGroupIndex)
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
                                            Image(systemName: "clock.arrow.circlepath")
                                                .foregroundColor(.accentColor)
                                        }

                                        Spacer()
                                        Image(
                                            systemName: (chapter.locked ?? false)
                                                ? "lock.fill" : "chevron.right"
                                        )
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
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack {
                            Button(action: {
                                isReversed.toggle()
                            }) {
                                Image(
                                    systemName: isReversed
                                        ? "arrow.up"
                                        : "arrow.down"
                                )
                            }

                            if allowEditing, plugin is Editable, manga.editable ?? true {
                                NavigationLink(destination: {
                                    UpdateChaptersModal(
                                        plugin: plugin as! any Editable,
                                        manga: manga,
                                        chapterGroupIndex: chapterGroupIndex
                                    )
                                }) {
                                    Image(systemName: "pencil")
                                }
                            }
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("close") {
                            dismiss()
                        }
                    }
                }
                .navigationTitleWithSubtitle(
                    title: Text(LocalizedStringKey(chapterGroupTitle)),
                    subtitle: Text("\(chapters.count) chapters")
                )
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
