//
//  UpdateChaptersModal.swift
//  mankai
//
//  Created by Travis XU on 3/7/2025.
//

import SwiftUI

struct UpdateChaptersModal: View {
    let plugin: any Editable
    let manga: DetailedManga
    let chapterGroupIndex: Int
    var isRootOfSheet: Bool

    private let chapterGroupTitle: String?

    @State private var chapters: [Chapter] = []
    @State private var showingAddAlert = false
    @State private var newChapterName = ""
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""

    @State private var chapterGroupId: String? = nil

    @Environment(\.dismiss) private var dismiss

    init(
        plugin: any Editable, manga: DetailedManga, chapterGroupIndex: Int,
        isRootOfSheet: Bool = false
    ) {
        self.plugin = plugin
        self.manga = manga
        self.chapterGroupIndex = chapterGroupIndex
        self.isRootOfSheet = isRootOfSheet
        chapterGroupTitle = manga.chapters.indices.contains(chapterGroupIndex)
            ? manga.chapters[chapterGroupIndex].title
            : nil
    }

    private func fetchChapters() {
        guard let groupId = chapterGroupId else { return }
        Task {
            do {
                let fetchedChapters = try await plugin.getChapters(groupId: groupId)
                chapters = fetchedChapters
            } catch {
                errorMessage = error.localizedDescription
                showingErrorAlert = true
            }
        }
    }

    private func moveChapter(from source: IndexSet, to destination: Int) {
        chapters.move(fromOffsets: source, toOffset: destination)

        let currentChapters = chapters
        Task {
            do {
                let ids = currentChapters.map { $0.id }
                try await plugin.arrangeChapterOrder(ids: ids)

                fetchChapters()
            } catch {
                errorMessage = error.localizedDescription
                showingErrorAlert = true
            }
        }
    }

    private func deleteChapter(at offsets: IndexSet) {
        let chaptersToDelete = offsets.map { chapters[$0] }
        chapters.remove(atOffsets: offsets)

        Task {
            do {
                for chapter in chaptersToDelete {
                    try await plugin.deleteChapter(id: chapter.id)
                }

                fetchChapters()
            } catch {
                errorMessage = error.localizedDescription
                showingErrorAlert = true
            }
        }
    }

    private func renameChapter(for chapterId: String, to newTitle: String) {
        Task {
            do {
                guard let groupId = chapterGroupId else {
                    throw MankaiErrorCode.chapterGroupNotFound.makeError()
                }

                try await plugin.upsertChapter(
                    EditableChapter(
                        id: chapterId, title: newTitle, chapterGroupId: groupId
                    )
                )

                fetchChapters()
            } catch {
                errorMessage = error.localizedDescription
                showingErrorAlert = true
            }
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button("add") {
                        showingAddAlert = true
                    }
                    .padding(.horizontal, 20)

                    ForEach(chapters, id: \.id) { chapter in
                        NavigationLink(destination: {
                            UpdateChapterModal(
                                plugin: plugin,
                                manga: manga,
                                chapter: chapter,
                                onRename: { id, title in
                                    renameChapter(for: id, to: title)
                                }
                            )
                        }) {
                            Text(chapter.title ?? chapter.id)
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 20)
                    }
                    .onMove(perform: moveChapter)
                    .onDelete(perform: deleteChapter)
                } header: {
                    Text("editChaptersInstructions")
                        .font(.caption)
                        .textCase(.none)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom)
                }
                .listRowInsets(EdgeInsets())
            }
            .navigationBarTitleDisplayMode(.inline)
            .apply {
                if isRootOfSheet {
                    $0
                        .navigationTitle(LocalizedStringKey(chapterGroupTitle ?? ""))
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                VStack {
                                    Text("editChapters")
                                        .font(.headline)
                                    Text(LocalizedStringKey(chapterGroupTitle ?? ""))
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
                } else {
                    $0
                }
            }
        }
        .alert("addChapter", isPresented: $showingAddAlert) {
            TextField("chapterTitle", text: $newChapterName)
            Button("add") {
                let trimmedName = newChapterName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedName.isEmpty {
                    Task {
                        do {
                            guard let groupId = chapterGroupId else {
                                throw MankaiErrorCode.chapterGroupNotFound.makeError()
                            }

                            try await plugin.upsertChapter(
                                EditableChapter(
                                    id: nil, title: trimmedName, chapterGroupId: groupId
                                )
                            )

                            fetchChapters()
                        } catch {
                            errorMessage = error.localizedDescription
                            showingErrorAlert = true
                        }
                    }
                }
                newChapterName = ""
            }
            Button("cancel", role: .cancel) {
                newChapterName = ""
            }
        } message: {
            Text("enterChapterTitle")
        }
        .alert("failedToEditChapters", isPresented: $showingErrorAlert) {
            Button("ok") {}
        } message: {
            Text(errorMessage)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(LocalizedStringKey(chapterGroupTitle ?? ""))
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text("editChapters")
                        .font(.headline)
                    Text(LocalizedStringKey(chapterGroupTitle ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            do {
                guard let chapterGroupTitle else {
                    dismiss()
                    return
                }

                if let groupId = try await plugin.getChapterGroupId(
                    mangaId: manga.id, title: chapterGroupTitle
                ) {
                    self.chapterGroupId = groupId
                    fetchChapters()
                } else {
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
                showingErrorAlert = true
            }
        }
    }
}
