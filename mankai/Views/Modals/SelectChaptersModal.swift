//
//  SelectChaptersModal.swift
//  mankai
//
//  Created by Travis XU on 14/2/2026.
//

import GRDB
import SwiftUI

private struct ChapterGroupEntry: Identifiable {
    var id: String {
        key
    }

    let key: String
    let chapters: [Chapter]
}

struct SelectChaptersModal: View {
    @Environment(\.dismiss) var dismiss
    let plugin: Plugin
    let detailedManga: DetailedManga
    let alreadyDownloaded: [String: Set<String>]?
    let downloadChapters: ([String: [Chapter]]) -> Void

    // chaptersKey -> set of selected chapter ids
    @State private var selectedChapters: [String: Set<String>] = [:]
    @State private var expandedGroup: String? = nil

    private var totalSelectedCount: Int {
        selectedChapters.values.reduce(0) { $0 + $1.count }
    }

    private var sortedChapterGroups: [ChapterGroupEntry] {
        detailedManga.chapters.map { ChapterGroupEntry(key: $0.key, chapters: $0.value) }
            .sorted { $0.chapters.count > $1.chapters.count }
    }

    private func isDownloaded(chapterId: String, groupKey: String) -> Bool {
        alreadyDownloaded?[groupKey]?.contains(chapterId) == true
    }

    private func isSelected(chapterId: String, groupKey: String) -> Bool {
        selectedChapters[groupKey]?.contains(chapterId) == true
    }

    private func toggleChapter(_ chapter: Chapter, groupKey: String) {
        var set = selectedChapters[groupKey] ?? []
        if set.contains(chapter.id) {
            set.remove(chapter.id)
        } else {
            set.insert(chapter.id)
        }
        selectedChapters[groupKey] = set
    }

    private func selectAllInGroup(_ groupKey: String, chapters: [Chapter]) {
        let selectable = chapters.filter { !isDownloaded(chapterId: $0.id, groupKey: groupKey) }
        let selectableIds = Set(selectable.map { $0.id })
        let currentSelected = selectedChapters[groupKey] ?? []

        if selectableIds.isSubset(of: currentSelected) {
            selectedChapters[groupKey] = currentSelected.subtracting(selectableIds)
        } else {
            selectedChapters[groupKey] = currentSelected.union(selectableIds)
        }
    }

    private func buildDownloadPayload() -> [String: [Chapter]] {
        var result: [String: [Chapter]] = [:]
        for (groupKey, selectedIds) in selectedChapters {
            guard !selectedIds.isEmpty else { continue }
            if let chapters = detailedManga.chapters[groupKey] {
                result[groupKey] = chapters.filter { selectedIds.contains($0.id) }
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedChapterGroups) { group in
                    Section {
                        chapterGroupRow(group: group)

                        if expandedGroup == group.key {
                            ForEach(group.chapters, id: \.id) { chapter in
                                chapterRow(chapter: chapter, groupKey: group.key)
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .principal) {
                    VStack {
                        Text("selectChapters")
                            .font(.headline)
                        if totalSelectedCount > 0 {
                            Text("\(totalSelectedCount) selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("download") {
                        let payload = buildDownloadPayload()
                        downloadChapters(payload)
                        dismiss()
                    }
                    .disabled(totalSelectedCount == 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    @ViewBuilder
    private func chapterGroupRow(group: ChapterGroupEntry) -> some View {
        let chapters = group.chapters
        let groupKey = group.key
        let downloadedSet = alreadyDownloaded?[groupKey] ?? []
        // calculate selectable chapters (those not already downloaded)
        let selectableChapters = chapters.filter { !downloadedSet.contains($0.id) }
        let selectableCount = selectableChapters.count

        // calculate currently selected count among selectable ones
        let currentlySelectedIds = selectedChapters[groupKey] ?? []
        let selectedSelectableCount = selectableChapters.filter { currentlySelectedIds.contains($0.id) }.count

        let isAllSelected = selectableCount > 0 && selectedSelectableCount == selectableCount
        let isPartiallySelected = selectedSelectableCount > 0 && selectedSelectableCount < selectableCount

        HStack(spacing: 12) {
            // Select All / Deselect All Checkbox
            if selectableCount > 0 {
                Button(action: {
                    selectAllInGroup(groupKey, chapters: chapters)
                }) {
                    Image(systemName: isAllSelected ? "checkmark.circle.fill" : (isPartiallySelected ? "minus.circle.fill" : "circle"))
                        .resizable()
                        .frame(width: 20, height: 20)
                        .foregroundColor(isAllSelected || isPartiallySelected ? .accentColor : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            } else {
                // Fully downloaded state
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundColor(.gray)
            }

            // Group Title and Info (Tapping this area toggles expansion)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(groupKey))
                            .foregroundColor(.primary)

                        Text("\(chapters.count) chapters")
                            .smallTagStyle()
                    }

                    Text("\(selectedSelectableCount) selected")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(expandedGroup == groupKey ? 90 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    if expandedGroup == groupKey {
                        expandedGroup = nil
                    } else {
                        expandedGroup = groupKey
                    }
                }
            }
        }
        .padding(.trailing, 4)
    }

    @ViewBuilder
    private func chapterRow(chapter: Chapter, groupKey: String) -> some View {
        let downloaded = isDownloaded(chapterId: chapter.id, groupKey: groupKey)
        let selected = isSelected(chapterId: chapter.id, groupKey: groupKey)

        Button(action: {
            toggleChapter(chapter, groupKey: groupKey)
        }) {
            HStack {
                Image(
                    systemName: downloaded
                        ? "checkmark.circle.fill"
                        : selected
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .foregroundColor(
                    downloaded
                        ? .gray
                        : selected
                        ? .accentColor
                        : .secondary
                )

                Text(chapter.title ?? chapter.id)
                    .foregroundColor(downloaded ? .secondary : .primary)

                Spacer()

                if downloaded {
                    Text("downloaded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .disabled(downloaded)
    }
}
