//
//  PluginSearchScreen.swift
//  mankai
//
//  Created by Travis XU on 27/6/2025.
//

import SwiftUI

struct PluginSearchScreen: View {
    let plugin: Plugin
    let query: String
    let pluginService = PluginService.shared

    @State var isLoading: Bool = false
    @State var mangas: [UInt: [Manga]] = [:]
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    private var allMangas: [Manga] {
        let sortedKeys = mangas.keys.sorted()
        return sortedKeys.flatMap { mangas[$0] ?? [] }
    }

    var body: some View {
        ScrollView {
            LazyVStack {
                MangasListView(mangas: allMangas, plugin: plugin)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }

                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        search()
                    }
            }
            .padding()
        }
        .overlay {
            if allMangas.isEmpty && isLoading {
                ProgressView()
            } else if allMangas.isEmpty && !mangas.isEmpty {
                ContentUnavailableView(
                    "noResultsFound",
                    systemImage: "magnifyingglass",
                    description: Text("noResultsFoundDescription")
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitleWithSubtitle(
            title: Text(plugin.name ?? plugin.id),
            subtitle: Text(query)
        )
        .onAppear {
            search()
        }
        .onReceive(pluginService.objectWillChange) {
            search()
        }
        .alert("failedToSearchManga", isPresented: $showErrorAlert) {
            Button("ok") {
                errorMessage = ""
            }
        } message: {
            if !errorMessage.isEmpty {
                Text(errorMessage)
            }
        }
    }

    private func search() {
        if isLoading {
            return
        }

        let maxPage = mangas.keys.max() ?? 0

        // reach the end of the list
        if mangas[maxPage]?.count == 0 {
            return
        }

        let page = maxPage + 1

        isLoading = true
        Task {
            do {
                let result = try await plugin.search(query, page: page)

                mangas[page] = result
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
                isLoading = false
            }
        }
    }
}
