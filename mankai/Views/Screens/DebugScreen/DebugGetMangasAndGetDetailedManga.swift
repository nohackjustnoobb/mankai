//
//  DebugGetMangasAndGetDetailedManga.swift
//  mankai
//
//  Created by Travis XU on 26/6/2025.
//

import SwiftUI

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension DebugGetMangasAndGetDetailedManga {
    private func statusText(_ status: Status?) -> String {
        guard let status = status else { return String(localized: "nil") }
        switch status {
        case .any:
            return String(localized: "any")
        case .onGoing:
            return String(localized: "onGoing")
        case .ended:
            return String(localized: "ended")
        }
    }

    private func chapterText(_ chapter: Chapter?) -> String {
        guard let chapter = chapter else { return String(localized: "nil") }
        if let title = chapter.title {
            return "\(title) (\(String(localized: "id")): \(chapter.id))"
        } else {
            return "\(String(localized: "id")): \(chapter.id)"
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date = date else { return String(localized: "nil") }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct DebugGetMangasAndGetDetailedManga: View {
    let mangaId: String
    let plugin: JsPlugin

    @State var detailedManga: DetailedManga? = nil
    @State var manga: Manga? = nil

    var body: some View {
        Group {
            if manga == nil && detailedManga == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if let manga = manga {
                        DebugMangas(
                            mangas: [manga], plugin: plugin, title: String(localized: "manga")
                        )
                    }

                    if let detailedManga = detailedManga {
                        Section("detailedManga") {
                            VStack(alignment: .leading, spacing: 8) {
                                Group {
                                    InfoRow(label: String(localized: "id"), value: detailedManga.id)
                                    InfoRow(
                                        label: String(localized: "cover"),
                                        value: detailedManga.cover ?? String(localized: "nil")
                                    )
                                    InfoRow(
                                        label: String(localized: "title"),
                                        value: detailedManga.title ?? String(localized: "nil")
                                    )
                                    InfoRow(
                                        label: String(localized: "status"),
                                        value: statusText(detailedManga.status)
                                    )
                                    InfoRow(
                                        label: String(localized: "description"),
                                        value: detailedManga.description ?? String(localized: "nil")
                                    )
                                    InfoRow(
                                        label: String(localized: "updatedAt"),
                                        value: dateText(detailedManga.updatedAt)
                                    )
                                    InfoRow(
                                        label: String(localized: "authors"),
                                        value: detailedManga.authors.isEmpty
                                            ? String(localized: "nil")
                                            : detailedManga.authors.joined(separator: ", ")
                                    )
                                    InfoRow(
                                        label: String(localized: "genres"),
                                        value: detailedManga.genres.isEmpty
                                            ? String(localized: "nil")
                                            : detailedManga.genres.map { $0.rawValue }.joined(
                                                separator: ", "
                                            )
                                    )
                                    InfoRow(
                                        label: String(localized: "latestChapter"),
                                        value: chapterText(detailedManga.latestChapter)
                                    )
                                    InfoRow(
                                        label: String(localized: "totalChapters"),
                                        value:
                                            "\(detailedManga.chapters.flatMap(\.chapters).count)"
                                    )
                                }
                            }
                        }

                        if detailedManga.chapters.isEmpty {
                            Section("chapters") {
                                Text("noChaptersAvailable")
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                        } else {
                            ForEach(detailedManga.chapters, id: \.title) { group in
                                Section(group.title) {
                                    ForEach(group.chapters, id: \.id) {
                                        chapter in
                                        NavigationLink(
                                            destination: DebugGetChapter(
                                                plugin: plugin,
                                                manga: detailedManga,
                                                chapter: chapter
                                            )
                                        ) {
                                            Text(chapterText(chapter))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            manga = try! await plugin.getMangas([mangaId]).first
            Logger.jsPlugin.debug("manga: \(manga ?? "nil" as Any)")

            detailedManga = try! await plugin.getDetailedManga(mangaId)
            Logger.jsPlugin.debug("detailedManga: \(detailedManga ?? "nil" as Any)")
        }
    }
}
