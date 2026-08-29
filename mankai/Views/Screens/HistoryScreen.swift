//
//  HistoryScreen.swift
//  mankai
//
//  Created by Travis XU on 12/7/2025.
//

import GRDB
import SwiftUI

struct HistoryScreen: View {
    @State private var records: [RecordModel] = []
    @State private var isLoading = false
    @State private var hasLoadedAll = false

    private let batchSize = 25

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "noHistory", systemImage: "clock.badge.xmark",
                        description: Text("noHistoryDescription"))
                } else {
                    List {
                        Section {
                            ForEach(Array(records.enumerated()), id: \.offset) { index, record in
                                HistoryItemView(record: record)
                                    .onAppear {
                                        if index == records.count - 1 && !hasLoadedAll {
                                            loadMoreRecords()
                                        }
                                    }
                            }

                            if isLoading { ProgressView().frame(maxWidth: .infinity) }
                        } header: {
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .navigationTitle("history").navigationBarTitleDisplayMode(.inline)
            .onAppear { if records.isEmpty { loadInitialRecords() } }
            .onReceive(HistoryService.shared.objectWillChange) { refreshRecords() }
        }
    }

    private func loadInitialRecords() {
        records = []
        hasLoadedAll = false
        loadMoreRecords()
    }

    private func loadMoreRecords() {
        guard !isLoading, !hasLoadedAll else { return }

        isLoading = true

        let newRecords = HistoryService.shared.getAll(limit: batchSize, offset: records.count)

        records.append(contentsOf: newRecords)
        hasLoadedAll = newRecords.count < batchSize
        isLoading = false
    }

    private func refreshRecords() {
        let newRecords = HistoryService.shared.getAll(limit: records.count)
        records = newRecords
    }
}

struct HistoryItemView: View {
    var record: RecordModel

    @State private var manga: Manga?
    @State private var plugin: Plugin?
    @State private var isLoading: Bool = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                NavigationLink(destination: {
                    if let manga = manga, let plugin = plugin {
                        MangaDetailsScreen(plugin: plugin, manga: manga)
                    } else {
                        ContentUnavailableView {
                            Label("somethingWentWrong", systemImage: "exclamationmark.circle")
                        } description: {
                            Text("failedToLoadMangaDetails")
                        }
                    }
                }) {
                    HStack(spacing: 12) {
                        MangaCoverView(coverUrl: manga?.cover, plugin: plugin)
                            .aspectRatio(3 / 4, contentMode: .fit)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(manga?.title ?? record.mangaId).font(.headline).lineLimit(1)

                            HStack {
                                if let chapterTitle = record.chapterTitle {
                                    Text(chapterTitle)

                                } else {
                                    Text(
                                        String(
                                            format: String(localized: "chapterFormat"),
                                            record.chapterId))
                                }

                                Text("•")
                                Text(
                                    String(
                                        format: String(localized: "historyPageFormat"),
                                        record.page + 1))
                            }
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)

                            Text(record.datetime.formatted()).font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .frame(height: 100).onAppear { loadMangaData() }
    }

    private func loadMangaData() {
        plugin =
            PluginService.shared.getPlugin(record.pluginId)
            ?? BrowseService.shared.getPlugin(record.pluginId)

        // Try to get manga from DbService
        if let mangaModel = getMangaModel(mangaId: record.mangaId, pluginId: record.pluginId),
            let infoData = mangaModel.info.data(using: .utf8)
        {
            do { manga = try JSONDecoder().decode(Manga.self, from: infoData) } catch {
                Logger.ui.error("Failed to decode manga data", error: error)
            }
        }

        // If not found locally, try fetching from plugin
        if manga == nil, let plugin = plugin, plugin.supports(.batchMangas) {
            Task {
                do { manga = try await plugin.getManga(id: record.mangaId) } catch {
                    Logger.ui.error("Failed to fetch manga from plugin", error: error)
                }

                isLoading = false
            }
        } else {
            isLoading = false
        }

        if manga == nil { Logger.ui.warning("Failed to load manga for record: \(record)") }
    }

    private func getMangaModel(mangaId: String, pluginId: String) -> MangaModel? {
        return try? DbService.shared.appDb?
            .read { db in
                try MangaModel.filter(
                    Column("mangaId") == mangaId && Column("pluginId") == pluginId
                )
                .fetchOne(db)
            }
    }
}
