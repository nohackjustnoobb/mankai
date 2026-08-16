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

    @State var selectedGenre: Genre
    @State private var selectedStatus: Status
    @State private var showingFilters = false

    @State private var tempSelectedGenre: Genre
    @State private var tempSelectedStatus: Status

    @State var isLoading: Bool = false
    @State var mangas: [UInt: [Manga]] = [:]
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var searchTask: Task<Void, Never>?

    private var hasActiveFilters: Bool {
        selectedGenre != .all || selectedStatus != .any
    }

    private var allMangas: [Manga] {
        let sortedKeys = mangas.keys.sorted()
        return sortedKeys.flatMap { mangas[$0] ?? [] }
    }

    init(plugin: Plugin, query: String, genre: Genre = .all, status: Status = .any) {
        self.plugin = plugin
        self.query = query
        _selectedGenre = State(initialValue: genre)
        _selectedStatus = State(initialValue: status)
        _tempSelectedGenre = State(initialValue: genre)
        _tempSelectedStatus = State(initialValue: status)
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
        .toolbar {
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
        .onAppear {
            search()
        }
        .onReceive(pluginService.objectWillChange) {
            search()
        }
        .onDisappear {
            searchTask?.cancel()
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

    private func setFilters(genre: Genre, status: Status) {
        guard selectedGenre != genre || selectedStatus != status else { return }

        searchTask?.cancel()
        selectedGenre = genre
        selectedStatus = status
        mangas = [:]
        isLoading = false
        search()
    }

    private func resetFilters() {
        tempSelectedGenre = .all
        tempSelectedStatus = .any
        setFilters(genre: .all, status: .any)
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
        let requestGenre = selectedGenre
        let requestStatus = selectedStatus

        isLoading = true
        searchTask = Task {
            do {
                let result = try await plugin.search(
                    query, page: page, genre: requestGenre, status: requestStatus
                )

                guard !Task.isCancelled,
                    requestGenre == selectedGenre,
                    requestStatus == selectedStatus
                else { return }

                mangas[page] = result
                isLoading = false
            } catch is CancellationError {
                // Ignore requests cancelled by a filter change or view dismissal.
            } catch {
                guard !Task.isCancelled,
                    requestGenre == selectedGenre,
                    requestStatus == selectedStatus
                else { return }

                errorMessage = error.localizedDescription
                showErrorAlert = true
                isLoading = false
            }
        }
    }
}
