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
    @State private var isParsing: Bool = false
    @State private var parsedMangas: [String: DetailedManga] = [:]
    @State private var parsingPaths: Set<String> = []
    @State private var parseErrors: [String: String] = [:]

    @State private var readerRoute: ReaderRoute?

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
                    case let .book(path, _):
                        if let manga = parsedMangas[path] {
                            let allChapters = manga.chapters.flatMap(\.chapters)
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
                        } else {
                            filePlaceholderView(
                                entity: entity,
                                isParsing: parsingPaths.contains(path),
                                errorMessage: parseErrors[path]
                            )
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
        .navigationDestination(item: $readerRoute) { params in
            ReaderScreen(
                plugin: params.plugin,
                manga: params.manga,
                downloadManga: params.downloadManga,
                chapterGroupIndex: params.chapterGroupIndex,
                chapter: params.chapter,
                initialPage: params.initialPage
            )
        }
    }

    /// If the manga has only a single chapter, skip the details screen and
    /// open the reader directly. The reading history is looked up so the
    /// reader can resume on the last-read page when available.
    private func navigateToReader(manga: DetailedManga) {
        let allChapters = manga.chapters.flatMap(\.chapters)
        guard let chapter = allChapters.first,
              let chapterGroupIndex = manga.chapters.firstIndex(where: { group in
                  group.chapters.contains { $0.id == chapter.id }
              })
        else { return }

        let page: Int?
        if let record = HistoryService.shared.get(mangaId: manga.id, pluginId: plugin.id),
           record.chapterId == chapter.id
        {
            page = record.page
        } else {
            page = nil
        }

        readerRoute = ReaderRoute(
            plugin: plugin,
            manga: manga,
            downloadManga: nil,
            chapterGroupIndex: chapterGroupIndex,
            chapter: chapter,
            initialPage: page
        )
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
        guard !isLoading, !isParsing else { return }

        isLoading = true
        errorMessage = nil
        parsedMangas = [:]
        parsingPaths = []
        parseErrors = [:]

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
                    self.isParsing = true
                }

                for entity in sorted {
                    guard case let .book(filePath, fileType) = entity else { continue }

                    await MainActor.run {
                        _ = self.parsingPaths.insert(filePath)
                    }

                    do {
                        let manga = try await plugin.parseFile(
                            path: filePath,
                            fileType: fileType
                        )
                        await MainActor.run {
                            self.parsedMangas[filePath] = manga
                            self.parsingPaths.remove(filePath)
                        }
                    } catch {
                        await MainActor.run {
                            self.parseErrors[filePath] = error.localizedDescription
                            self.parsingPaths.remove(filePath)
                        }
                    }
                }

                await MainActor.run {
                    self.isParsing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    self.isParsing = false
                }
            }
        }
    }

    private func thumbnailView<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
    }

    private func directoryView(entity: EntityType) -> some View {
        VStack(spacing: 8) {
            thumbnailView {
                Image("FolderIcon")
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        Image("FolderIcon")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(systemImageColor ?? .accentColor)
                            .blendMode(.hue)
                    }
                    .compositingGroup()
            }

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
            thumbnailView {
                MangaCoverView(coverUrl: manga.cover, plugin: plugin)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Text(entity.name(using: manga))
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func filePlaceholderView(
        entity: EntityType,
        isParsing: Bool,
        errorMessage: String?
    ) -> some View {
        let fileType: String
        if case let .book(_, type) = entity {
            fileType = type
        } else {
            fileType = ""
        }

        return VStack(spacing: 8) {
            thumbnailView {
                ZStack(alignment: .bottomLeading) {
                    Image("DocumentIcon")
                        .resizable()
                        .scaledToFill()
                        .clipped()

                    if errorMessage != nil {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.orange)
                            .padding(12)
                            .background(.regularMaterial, in: Circle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if isParsing {
                        ProgressView()
                            .padding(12)
                            .background(.regularMaterial, in: Circle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    Text(fileType.uppercased())
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            errorMessage == nil ? Color.primary : Color.orange
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .padding(12)
                }
            }

            Text(entity.name)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .help(errorMessage ?? "")
    }
}
