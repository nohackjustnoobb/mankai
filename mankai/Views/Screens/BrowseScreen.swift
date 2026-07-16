//
//  BrowseScreen.swift
//  mankai
//
//  Created by Travis XU on 14/7/2026.
//

import SwiftUI

struct BrowseScreen: View {
    let plugin: BrowsablePlugin
    let path: String?
    let systemImageColor: Color?

    @Environment(\.openURL) private var openURL

    @State private var entities: [EntityType] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    @State private var showReaderScreen = false
    @State private var readerManga: DetailedManga? = nil
    @State private var readerChapter: Chapter? = nil
    @State private var readerChapterKey: String? = nil
    @State private var readerPage: Int? = nil

    init(plugin: BrowsablePlugin, path: String? = nil, systemImageColor: Color? = nil) {
        self.plugin = plugin
        self.path = path
        self.systemImageColor = systemImageColor ?? plugin.systemImageColor
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 100), spacing: 20),
                ],
                spacing: 20
            ) {
                ForEach(Array(entities.enumerated()), id: \.offset) { _, entity in
                    switch entity {
                    case let .directory(dirPath):
                        NavigationLink(
                            destination: BrowseScreen(plugin: plugin, path: dirPath)
                        ) {
                            directoryView(entity: entity)
                        }
                        .buttonStyle(.plain)
                    case let .book(manga, _):
                        let allChapters = manga.chapters.values.flatMap { $0 }
                        if allChapters.count == 1 {
                            Button {
                                navigateToReader(manga: manga)
                            } label: {
                                mangaView(manga: manga, entity: entity)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(
                                destination: MangaDetailsScreen(
                                    plugin: plugin,
                                    manga: manga.toManga()
                                )
                            ) {
                                mangaView(manga: manga, entity: entity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if folderURL != nil {
                    Button {
                        openInFilesApp()
                    } label: {
                        Label("openInFiles", systemImage: "folder")
                    }
                }
            }
        }
        .overlay {
            if isLoading && entities.isEmpty {
                ProgressView {
                    Text("browseScreenLoadingHint")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else if let errorMessage = errorMessage {
                ContentUnavailableView(
                    "failedToLoadList",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if entities.isEmpty {
                ContentUnavailableView(
                    "noEntities",
                    systemImage: "tray",
                    description: Text("noEntitiesDescription")
                )
            }
        }
        .onAppear {
            loadEntities()
        }
        .navigationDestination(isPresented: $showReaderScreen) {
            if let readerManga = readerManga,
               let readerChapter = readerChapter,
               let readerChapterKey = readerChapterKey
            {
                ReaderScreen(
                    plugin: plugin,
                    manga: readerManga,
                    downloadManga: nil,
                    chaptersKey: readerChapterKey,
                    chapter: readerChapter,
                    initialPage: readerPage
                )
            }
        }
    }

    /// If the manga has only a single chapter, skip the details screen and
    /// open the reader directly. The reading history is looked up so the
    /// reader can resume on the last-read page when available.
    private func navigateToReader(manga: DetailedManga) {
        let allChapters = manga.chapters.values.flatMap { $0 }
        guard let chapter = allChapters.first,
              let chaptersKey = manga.chapters.first(where: { _, chapters in
                  chapters.contains { $0.id == chapter.id }
              })?.key
        else { return }

        let page: Int?
        if let record = HistoryService.shared.get(mangaId: manga.id, pluginId: plugin.id),
           record.chapterId == chapter.id
        {
            page = record.page
        } else {
            page = nil
        }

        readerManga = manga
        readerChapter = chapter
        readerChapterKey = chaptersKey
        readerPage = page
        showReaderScreen = true
    }

    private var navigationTitle: String {
        if let path = path, !path.isEmpty {
            return (path as NSString).lastPathComponent
        }
        return plugin.name ?? plugin.id
    }

    private var folderURL: URL? {
        plugin.absoluteURL(for: path)
    }

    private func openInFilesApp() {
        guard let folderURL else { return }
        let path = folderURL.standardizedFileURL.path
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        if let url = URL(string: "shareddocuments://\(encoded)") {
            openURL(url)
        }
    }

    private func loadEntities() {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let result = try await plugin.getEntities(path: path)
                let sorted = result.sorted { lhs, rhs in
                    switch (lhs, rhs) {
                    case (.directory, .book): return true
                    case (.book, .directory): return false
                    default:
                        return lhs.fileName.localizedStandardCompare(rhs.fileName) == .orderedAscending
                    }
                }
                await MainActor.run {
                    self.entities = sorted
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func directoryView(entity: EntityType) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(systemImageColor ?? .accentColor)
                .aspectRatio(1, contentMode: .fit)

            Text(entity.name)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func mangaView(manga: DetailedManga, entity: EntityType) -> some View {
        VStack(spacing: 8) {
            MangaCoverView(coverUrl: manga.cover, plugin: plugin)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(entity.name)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}
