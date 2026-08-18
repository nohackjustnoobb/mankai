//
//  BrowseScreen.swift
//  mankai
//
//  Created by Travis XU on 14/7/2026.
//

import SwiftUI

struct BrowseScreen: View {
    let plugin: BrowsablePlugin
    let entry: Entity?
    let systemImageColor: Color?

    @Environment(\.openURL) private var openURL

    @State private var entities: [Entity] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var isParsing: Bool = false
    @State private var parsedMangas: [String: DetailedManga] = [:]
    @State private var parsingPaths: Set<String> = []
    @State private var parseErrors: [String: String] = [:]

    init(
        plugin: BrowsablePlugin,
        entry: Entity? = nil,
        systemImageColor: Color? = nil
    ) {
        self.plugin = plugin
        self.entry = entry
        self.systemImageColor = systemImageColor ?? plugin.systemImageColor
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 100), spacing: 20)
                ],
                spacing: 20
            ) {
                ForEach(Array(entities.enumerated()), id: \.offset) { _, entity in
                    switch entity.type {
                    case .directory:
                        NavigationLink(
                            destination: BrowseScreen(plugin: plugin, entry: entity)
                        ) {
                            directoryView(entity: entity)
                        }
                        .buttonStyle(.plain)
                    case .book:
                        if let manga = parsedMangas[entity.path] {
                            NavigationLink(
                                destination: MangaDetailsScreen(
                                    plugin: plugin,
                                    manga: manga.toManga()
                                )
                            ) {
                                mangaView(manga: manga, entity: entity)
                            }
                            .buttonStyle(.plain)
                        } else {
                            filePlaceholderView(
                                entity: entity,
                                isParsing: parsingPaths.contains(entity.path),
                                errorMessage: parseErrors[entity.path]
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
    }

    private var navigationTitle: String {
        if let entry {
            return entry.displayName
        }
        return plugin.name ?? plugin.id
    }

    private var folderURL: URL? {
        plugin.absoluteURL(for: entry?.path)
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
                let result = try await plugin.getEntities(path: entry?.path)
                let sorted = result.sorted { lhs, rhs in
                    switch (lhs.type, rhs.type) {
                    case (.directory, .book): return true
                    case (.book, .directory): return false
                    default:
                        return lhs.name.localizedStandardCompare(rhs.name)
                            == .orderedAscending
                    }
                }
                await MainActor.run {
                    self.entities = sorted
                    self.isLoading = false
                    self.isParsing = true
                }

                for entity in sorted {
                    guard case .book(let fileType) = entity.type else { continue }
                    let filePath = entity.path

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
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
    }

    private func directoryView(entity: Entity) -> some View {
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

            Text(entity.displayName)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func mangaView(manga: DetailedManga, entity: Entity) -> some View {
        VStack(spacing: 8) {
            thumbnailView {
                MangaCoverView(coverUrl: manga.cover, plugin: plugin)
            }

            Text(entity.displayName(using: manga))
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func filePlaceholderView(
        entity: Entity,
        isParsing: Bool,
        errorMessage: String?
    ) -> some View {
        let fileType: String
        if case .book(let type) = entity.type {
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

            Text(entity.displayName)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .help(errorMessage ?? "")
    }
}
