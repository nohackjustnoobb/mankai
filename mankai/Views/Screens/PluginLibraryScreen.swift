//
//  PluginLibraryScreen.swift
//  mankai
//
//  Created by Travis XU on 27/6/2025.
//

import SwiftUI

struct PluginLibraryScreen: View {
    let plugin: Plugin

    @State var selectedGenre: Genre = .all
    @State private var selectedStatus: Status = .any
    @State private var showingFilters = false

    @State private var tempSelectedGenre: Genre = .all
    @State private var tempSelectedStatus: Status = .any

    @State private var isLoading: Bool = false
    @State private var mangasList: [String: [UInt: [Manga]]] = [:]
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    @State private var searchQuery: String = ""
    @State private var searchSuggestions: [String] = []
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var navigateToSearch: Bool = false

    private var hasActiveFilters: Bool {
        selectedGenre != .all || selectedStatus != .any
    }

    private var allMangas: [Manga] {
        let key = "\(selectedGenre.rawValue)_\(selectedStatus.rawValue)"

        guard let mangas = mangasList[key] else {
            return []
        }

        let sortedKeys = mangas.keys.sorted()
        return sortedKeys.flatMap { mangas[$0] ?? [] }
    }

    private var hasLoadedCurrentFilter: Bool {
        let key = "\(selectedGenre.rawValue)_\(selectedStatus.rawValue)"
        return mangasList[key] != nil
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack {
                    MangasListView(mangas: allMangas, plugin: plugin)
                        .id("mangasList")

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                    }

                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            loadList()
                        }
                }
                .padding()
            }
            .overlay {
                if allMangas.isEmpty && isLoading {
                    ProgressView()
                } else if allMangas.isEmpty && hasLoadedCurrentFilter {
                    ContentUnavailableView(
                        "noEntities",
                        systemImage: "tray",
                        description: Text("noEntitiesDescription")
                    )
                }
            }
            .onChange(of: selectedGenre, initial: false) { _, _ in
                proxy.scrollTo("mangasList", anchor: .top)
            }
            .onChange(of: selectedStatus, initial: false) { _, _ in
                proxy.scrollTo("mangasList", anchor: .top)
            }
        }
        .navigationTitle("library")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchQuery, prompt: "searchManga") {
            ForEach(searchSuggestions, id: \.self) { suggestion in
                Label(suggestion, systemImage: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .searchCompletion(suggestion)
            }
        }
        .onSubmit(of: .search) {
            performSearch()
        }
        .onChange(of: searchQuery, initial: false) { _, newQuery in
            getSearchSuggestions(for: newQuery)
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .navigationDestination(isPresented: $navigateToSearch) {
            PluginSearchScreen(plugin: plugin, query: searchQuery)
        }
        .sheet(isPresented: $showingFilters) {
            NavigationView {
                List {
                    Section {
                        Picker("genre", selection: $tempSelectedGenre) {
                            Text(LocalizedStringKey(Genre.all.rawValue))
                                .tag(Genre.all)

                            ForEach(plugin.availableGenres, id: \.self) { genre in
                                Text(LocalizedStringKey(genre.rawValue))
                                    .tag(genre)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("status", selection: $tempSelectedStatus) {
                            Text(Status.any.localizedName).tag(Status.any)
                            Text(Status.onGoing.localizedName).tag(Status.onGoing)
                            Text(Status.ended.localizedName).tag(Status.ended)
                        }
                        .pickerStyle(.menu)
                    } header: {
                        Spacer(minLength: 0)
                    }

                    Section {
                        Button(
                            "reset",
                            role: .destructive,
                            action: {
                                resetFilters()
                                showingFilters = false
                            }
                        )
                    }
                }
                .navigationTitle("filters")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: {
                            tempSelectedGenre = selectedGenre
                            tempSelectedStatus = selectedStatus
                            showingFilters = false
                        }) {
                            Text("cancel")
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: {
                            setFilters(genre: tempSelectedGenre, status: tempSelectedStatus)
                            showingFilters = false
                        }) {
                            Text("done")
                        }
                    }
                }
            }
            .presentationDetents([.medium])
            .onAppear {
                tempSelectedGenre = selectedGenre
                tempSelectedStatus = selectedStatus
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text(plugin.name ?? plugin.id)
                        .font(.headline)
                    Text("library")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showingFilters = true
                }) {
                    ZStack {
                        Image(systemName: "line.3.horizontal.decrease.circle")

                        if hasActiveFilters {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .offset(x: 8, y: -8)
                        }
                    }
                }
            }
        }
        .onAppear {
            loadList()
        }
        .alert("failedToLoadList", isPresented: $showErrorAlert) {
            Button("ok") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func loadList() {
        if isLoading {
            return
        }

        let key = "\(selectedGenre.rawValue)_\(selectedStatus.rawValue)"

        let maxPage = mangasList[key]?.keys.max() ?? 0

        // reach the end of the list
        if mangasList[key]?[maxPage]?.count == 0 {
            return
        }

        let page = maxPage + 1

        isLoading = true
        Task {
            do {
                let result = try await plugin.getList(
                    page: page, genre: selectedGenre, status: selectedStatus
                )

                if mangasList[key] == nil {
                    mangasList[key] = [:]
                }

                mangasList[key]![page] = result

                isLoading = false
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func setGenre(_ genre: Genre) {
        guard genre != selectedGenre else { return }

        selectedGenre = genre
        loadList()
    }

    private func setStatus(_ status: Status) {
        guard status != selectedStatus else { return }

        selectedStatus = status
        loadList()
    }

    private func setFilters(genre: Genre, status: Status) {
        if selectedGenre != genre {
            selectedGenre = genre
        }

        if selectedStatus != status {
            selectedStatus = status
        }

        loadList()
    }

    private func resetFilters() {
        tempSelectedGenre = .all
        tempSelectedStatus = .any
        setFilters(genre: .all, status: .any)
    }

    private func getSearchSuggestions(for query: String) {
        searchTask?.cancel()

        guard !query.isEmpty else {
            searchSuggestions = []
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)

            guard !Task.isCancelled else { return }

            do {
                let suggestions = try await plugin.getSuggestions(query)
                guard !Task.isCancelled else { return }
                searchSuggestions = suggestions
            } catch {
                searchSuggestions = []
            }
        }
    }

    private func performSearch() {
        guard !searchQuery.isEmpty else { return }
        navigateToSearch = true
    }
}
