//
//  HomeTab.swift
//  mankai
//
//  Created by Travis XU on 20/6/2025.
//

import GRDB
import SwiftUI

private enum HomeMangaStatus: String, CaseIterable {
    case all
    case onGoing
    case ended
    case updated
}

private enum HomeDataSource: String, CaseIterable {
    case collections
    case downloads
}

struct HomeTab: View {
    private let pluginService = PluginService.shared
    private let browseService = BrowseService.shared

    @State private var mangas: [String: Manga] = [:]
    @State private var plugins: [String: Plugin] = [:]
    @State private var records: [String: RecordModel] = [:]
    @State private var saveds: [String: SavedModel] = [:]
    @State private var orders: [String] = []

    // Filter & Search
    @State private var searchText: String = ""
    @State private var showPlugins: [String] = []
    @State private var status: HomeMangaStatus = .all
    @State private var dataSource: HomeDataSource = .collections
    @State private var filteredOrders: [String] = []
    @State private var showingFilters = false
    @State private var showingDownloads = false

    /// Downloads state
    @State private var isLoadingDownloads = false

    /// Update state
    @State private var isRefreshing = false

    /// First initialization and connectivity check
    @State private var showNoInternetAlert = false

    // Navigation from download modal
    @State private var navigateToManga: Manga? = nil
    @State private var navigateToPlugin: Plugin? = nil
    @State private var navigateToDetails: Bool = false

    private var hasActiveFilters: Bool {
        if dataSource == .downloads {
            return false
        }

        let allPluginIds = Set(allPlugins.keys)
        let showSet = Set(showPlugins)
        return showSet != allPluginIds
    }

    private var isDownloadsMode: Bool {
        dataSource == .downloads
    }

    private var allPlugins: [String: Plugin] {
        var pluginsById = Dictionary(
            uniqueKeysWithValues: pluginService.plugins.map { ($0.id, $0) }
        )

        for plugin in browseService.plugins where pluginsById[plugin.id] == nil {
            pluginsById[plugin.id] = plugin
        }

        return pluginsById
    }

    private var availablePlugins: [Plugin] {
        return allPlugins.values.sorted { plugin1, plugin2 in
            let name1 = plugin1.name ?? plugin1.id
            let name2 = plugin2.name ?? plugin2.id
            return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !isDownloadsMode && orders.isEmpty {
                    ContentUnavailableView(
                        "noSavedManga",
                        systemImage: "bookmark.slash",
                        description: Text("noSavedMangaDescription")
                    )
                } else if isDownloadsMode && orders.isEmpty && isLoadingDownloads {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredOrders.isEmpty {
                    ContentUnavailableView(
                        "noResultsFound",
                        systemImage: "magnifyingglass",
                        description: Text("noResultsFoundDescription")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            MangasListView(
                                mangas: mangas,
                                plugins: plugins,
                                keys: filteredOrders,
                                records: records,
                                saveds: saveds,
                                showNotRead: true,
                                allowUnsupportedDetailsNavigation: isDownloadsMode
                            )
                        }
                        .padding()
                    }
                    .refreshable {
                        if isDownloadsMode {
                            await reloadDownloads()
                        } else {
                            await performUpdate()
                        }
                    }
                }
            }
            .navigationTitle("home")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("source", selection: $dataSource) {
                            Text("collections").tag(HomeDataSource.collections)
                            Text("downloads").tag(HomeDataSource.downloads)
                        }

                        Picker("status", selection: $status) {
                            Text("all").tag(HomeMangaStatus.all)
                            Text("onGoing").tag(HomeMangaStatus.onGoing)
                            Text("ended").tag(HomeMangaStatus.ended)
                            Text("updated").tag(HomeMangaStatus.updated)
                        }
                        .disabled(isDownloadsMode)
                    } label: {
                        Text(
                            LocalizedStringKey(
                                isDownloadsMode || status == .all
                                    ? dataSource.rawValue : status.rawValue))
                    }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: {
                        showingDownloads = true
                    }) {
                        Image(systemName: "arrow.down.circle")
                    }

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
                    .disabled(isDownloadsMode)
                }
            }
            .searchable(
                text: $searchText,
                prompt: isDownloadsMode
                    ? LocalizedStringKey("searchDownloadedManga")
                    : LocalizedStringKey("searchSavedManga")
            )
            .onChange(of: searchText) {
                filterManga()
            }
            .onChange(of: status) {
                filterManga()
            }
            .onChange(of: dataSource) {
                Task {
                    if isDownloadsMode {
                        await reloadDownloads()
                    } else {
                        updateSaved()
                    }
                }
            }
            .onAppear {
                initializeShowPlugins()

                if isDownloadsMode {
                    Task {
                        await reloadDownloads()
                    }
                } else {
                    updateSaved()
                }
            }
            .onReceive(pluginService.objectWillChange) {
                initializeShowPlugins()
                if !isDownloadsMode {
                    updateSaved()
                }
            }
            .onReceive(browseService.objectWillChange) {
                initializeShowPlugins()
                if !isDownloadsMode {
                    updateSaved()
                }
            }
            .onReceive(SavedService.shared.objectWillChange) {
                if !isDownloadsMode {
                    updateSaved()
                }
            }
            .onReceive(HistoryService.shared.objectWillChange) {
                updateRecord()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            ) { _ in
                checkInternetAndPrompt()
            }
            .sheet(isPresented: $showingFilters) {
                HomeFilterModal(
                    isPresented: $showingFilters,
                    showPlugins: $showPlugins,
                    availablePlugins: availablePlugins,
                    onReset: resetFilters,
                    onApply: filterManga
                )
            }
            .sheet(isPresented: $showingDownloads) {
                DownloadModal { plugin, manga in
                    navigateToDetails = true
                    navigateToPlugin = plugin
                    navigateToManga = manga

                    showingDownloads = false
                }
            }
            .navigationDestination(isPresented: $navigateToDetails) {
                if let plugin = navigateToPlugin, let manga = navigateToManga {
                    MangaDetailsScreen(plugin: plugin, manga: manga)
                }
            }
            .alert("noInternetConnection", isPresented: $showNoInternetAlert) {
                Button("switch") {
                    dataSource = .downloads
                }

                Button("cancel", role: .cancel) {}
            } message: {
                Text("noInternetConnectionMessage")
            }
        }
    }

    private func updateSaved() {
        var mangas: [String: Manga] = [:]
        var plugins: [String: Plugin] = [:]
        var saveds: [String: SavedModel] = [:]

        let savedList: [SavedModel] = SavedService.shared.getAll()
        for saved in savedList {
            let key = "\(saved.pluginId)+\(saved.mangaId)"

            if let plugin = allPlugins[saved.pluginId] {
                plugins[key] = plugin
            }

            if let mangaModel = try? DbService.shared.appDb?.read({ db in
                try MangaModel.filter(
                    Column("mangaId") == saved.mangaId && Column("pluginId") == saved.pluginId
                ).fetchOne(db)
            }) {
                if let mangaData = mangaModel.info.data(using: .utf8),
                    let mangaDict = try? JSONSerialization.jsonObject(with: mangaData)
                        as? [String: Any],
                    let manga = Manga(from: mangaDict)
                {
                    mangas[key] = manga
                }
            }

            saveds[key] = saved
        }

        self.mangas = mangas
        self.plugins = plugins
        self.saveds = saveds

        updateRecord()
    }

    private func updateRecord() {
        if isDownloadsMode {
            updateDownloadRecords(for: orders)
            return
        }

        var records: [String: RecordModel] = [:]
        let ids = saveds.values.map { (mangaId: $0.mangaId, pluginId: $0.pluginId) }
        let historyRecords = HistoryService.shared.get(ids: ids)

        for record in historyRecords {
            let key = "\(record.pluginId)+\(record.mangaId)"
            if saveds[key] != nil {
                records[key] = record
            }
        }

        self.records = records

        sortSaved()
    }

    private func sortSaved() {
        let keys = mangas.keys

        let sortedKeys = keys.sorted { key1, key2 in
            let savedDate1 = saveds[key1]?.datetime
            let recordDate1 = records[key1]?.datetime
            let savedDate2 = saveds[key2]?.datetime
            let recordDate2 = records[key2]?.datetime

            let newerDate1 = [savedDate1, recordDate1].compactMap { $0 }.max()
            let newerDate2 = [savedDate2, recordDate2].compactMap { $0 }.max()

            switch (newerDate1, newerDate2) {
            case (let date1?, let date2?):
                if abs(date1.timeIntervalSince(date2)) < 1e-3 {
                    return key1 < key2
                }
                return date1 > date2
            case (nil, _):
                return false
            case (_, nil):
                return true
            }
        }

        orders = sortedKeys
        filterManga()
    }

    private func filterManga() {
        var filtered = orders

        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { key in
                mangas[key]?.title?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }

        if !isDownloadsMode {
            // Filter by shown plugins
            filtered = filtered.filter { key in
                let pluginId = key.split(separator: "+").first.map(String.init) ?? ""
                return showPlugins.contains(pluginId)
            }

            // Filter by status
            if status != .all {
                filtered = filtered.filter { key in
                    guard let manga = mangas[key], let saved = saveds[key] else { return false }

                    switch status {
                    case .all:
                        return true
                    case .onGoing:
                        return manga.status == .onGoing
                    case .ended:
                        return manga.status == .ended
                    case .updated:
                        return saved.updates
                    }
                }
            }
        }

        filteredOrders = filtered
    }

    private func setStatus(_ newStatus: HomeMangaStatus) {
        guard newStatus != status else { return }
        status = newStatus
        filterManga()
    }

    private func initializeShowPlugins() {
        showPlugins = Array(allPlugins.keys)
    }

    private func resetFilters() {
        showPlugins = Array(allPlugins.keys)
        status = .all
        filterManga()
    }

    private func performUpdate() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        try? await UpdateService.shared.update()

        isRefreshing = false
    }

    private func reloadDownloads() async {
        isLoadingDownloads = true
        defer { isLoadingDownloads = false }

        mangas = [:]
        plugins = [:]
        saveds = [:]
        records = [:]
        orders = []
        filteredOrders = []
        var downloadOrders: [String] = []

        if let downloadedMangas = try? await DownloadPlugin.shared.getDownloadedMangas() {
            for manga in downloadedMangas.compactMap({ $0.toManga() }) {
                if let pluginId = manga.meta {
                    let key = "\(pluginId)+\(manga.id)"

                    mangas[key] = manga
                    plugins[key] = allPlugins[pluginId] ?? DummyPlugin(pluginId)
                    downloadOrders.append(key)
                }
            }
        }

        orders = downloadOrders
        updateDownloadRecords(for: downloadOrders)
        filterManga()
    }

    private func updateDownloadRecords(for keys: [String]) {
        guard !keys.isEmpty else { return }

        let ids = keys.compactMap { key -> (mangaId: String, pluginId: String)? in
            let parts = key.split(separator: "+", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (mangaId: parts[1], pluginId: parts[0])
        }

        let fetchedRecords = HistoryService.shared.get(ids: ids)

        if keys == orders {
            records = [:]
        }

        for record in fetchedRecords {
            let key = "\(record.pluginId)+\(record.mangaId)"
            records[key] = record
        }
    }

    private func checkInternetAndPrompt() {
        guard !isDownloadsMode else { return }

        let reachability = Reach()
        let status = reachability.connectionStatus()

        switch status {
        case .offline, .unknown:
            showNoInternetAlert = true
        default:
            break
        }
    }
}
