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

    @State private var entities: [EntityType] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    init(plugin: BrowsablePlugin, path: String? = nil) {
        self.plugin = plugin
        self.path = path
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 100), spacing: 12),
                ],
                spacing: 10
            ) {
                ForEach(Array(entities.enumerated()), id: \.offset) { _, entity in
                    switch entity {
                    case let .directory(dirPath):
                        NavigationLink(
                            destination: BrowseScreen(plugin: plugin, path: dirPath)
                        ) {
                            directoryView(path: dirPath)
                        }
                        .buttonStyle(.plain)
                    case let .book(manga):
                        NavigationLink(
                            destination: MangaDetailsScreen(
                                plugin: plugin,
                                manga: manga.toManga()
                            )
                        ) {
                            mangaView(manga: manga)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading && entities.isEmpty {
                ProgressView()
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
        if let path = path, !path.isEmpty {
            return (path as NSString).lastPathComponent
        }
        return plugin.name ?? plugin.id
    }

    private func loadEntities() {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let result = try await plugin.getEntities(path: path)
                await MainActor.run {
                    self.entities = result
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

    @ViewBuilder
    private func directoryView(path: String) -> some View {
        let name = (path as NSString).lastPathComponent

        VStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.tint)
                .aspectRatio(1, contentMode: .fit)

            Text(name)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func mangaView(manga: DetailedManga) -> some View {
        VStack(spacing: 8) {
            MangaCoverView(coverUrl: manga.cover, plugin: plugin)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(manga.title ?? manga.id)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}
