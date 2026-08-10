//
//  MangaDetailsScreen.swift
//  mankai
//
//  Created by Travis XU on 29/6/2025.
//

import SwiftUI
import WrappingHStack

struct MangaDetailsScreen: View {
    @ObservedObject var plugin: Plugin
    let manga: Manga

    @State private var detailedManga: DetailedManga? = nil

    @State private var showingChaptersModal = false
    @State private var selectedChapterGroupIndex: Int? = nil
    @State private var isReversed = true

    @State private var readerRoute: ReaderRoute?

    @State private var isUpdateMangaModalPresented = false
    @State private var isUpdateChaptersModalPresented = false
    @State private var isSelectChaptersModalPresented = false

    @State private var selectedGenre: Genre? = nil
    @State private var showPluginLibraryScreen = false

    @State private var searchQuery: String? = nil
    @State private var showPluginSearchScreen = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var record: RecordModel? = nil
    @State private var saved: SavedModel? = nil

    /// Offline access
    private var downloadMangaId: String {
        return "\(plugin.id)+\(manga.id)"
    }

    @State private var downloadManga: DetailedManga?
    @State private var downloadedChapterIds: Set<String>?

    private var mangaData: DetailedManga? {
        return detailedManga ?? downloadManga
    }

    private var selectedChapterGroup: ChapterGroup? {
        guard let mangaData,
            let selectedChapterGroupIndex,
            mangaData.chapters.indices.contains(selectedChapterGroupIndex)
        else {
            return nil
        }

        return mangaData.chapters[selectedChapterGroupIndex]
    }

    init(plugin: Plugin, manga: Manga) {
        self.plugin = plugin
        self.manga = manga
    }

    private func updateRecord() {
        record = HistoryService.shared.get(mangaId: manga.id, pluginId: plugin.id)
    }

    private func updateSaved() {
        saved = SavedService.shared.get(mangaId: manga.id, pluginId: plugin.id)
    }

    private func navigateToChapter(
        _ chapter: Chapter, page: Int? = nil, chapterGroupIndex: Int? = nil
    ) {
        guard let mangaData,
            let readerChapterGroupIndex = chapterGroupIndex ?? selectedChapterGroupIndex
        else { return }

        showingChaptersModal = false
        readerRoute = ReaderRoute(
            plugin: plugin,
            manga: mangaData,
            downloadManga: downloadManga,
            chapterGroupIndex: readerChapterGroupIndex,
            chapter: chapter,
            initialPage: page
        )
    }

    private func scrollToRecord(proxy: ScrollViewProxy) {
        guard let record = record, let mangaData = mangaData else { return }

        guard
            let targetIndex = mangaData.chapters.firstIndex(where: { group in
                group.chapters.contains { $0.id == record.chapterId }
            })
        else {
            return
        }

        if selectedChapterGroupIndex == targetIndex {
            proxy.scrollTo(record.chapterId, anchor: .center)
        } else {
            selectedChapterGroupIndex = targetIndex
        }
    }

    private func handleReadContinueAction() {
        if let record = record, let mangaData = mangaData {
            for (groupIndex, group) in mangaData.chapters.enumerated() {
                if let chapter = group.chapters.first(where: {
                    $0.id == record.chapterId
                }) {
                    navigateToChapter(
                        chapter, page: record.page, chapterGroupIndex: groupIndex
                    )
                    return
                }
            }
        }

        if let mangaData = mangaData {
            if let group = mangaData.chapters.first,
                let chapter = group.chapters.first
            {
                navigateToChapter(chapter, chapterGroupIndex: 0)
            }
        }
    }

    private func handleBookmarkAction() {
        Task {
            do {
                if saved != nil {
                    let _ = try await SavedService.shared.remove(
                        mangaId: manga.id, pluginId: plugin.id)
                } else {
                    let newSaved = SavedModel(
                        mangaId: manga.id,
                        pluginId: plugin.id,
                        datetime: Date(),
                        updates: false,
                        latestChapter: manga.latestChapter?.encode() ?? "",
                        shouldSync: plugin.shouldSync
                    )

                    let mangaInfo: String
                    if let mangaData = try? JSONEncoder().encode(manga) {
                        mangaInfo = String(data: mangaData, encoding: .utf8) ?? "{}"
                    } else {
                        mangaInfo = "{}"
                    }

                    let mangaModel = MangaModel(
                        mangaId: manga.id,
                        pluginId: plugin.id,
                        info: mangaInfo
                    )

                    let _ = try await SavedService.shared.add(saved: newSaved, manga: mangaModel)
                }
            } catch {
                Logger.ui.error("Failed to delete or create SavedData")
            }
        }
    }

    var info: some View {
        List {
            if mangaData != nil && detailedManga == nil {
                Section {
                    Text("usingDownloadMangaDescription")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } header: {
                    Spacer(minLength: 0)
                }
            }

            if let remarks = mangaData?.remarks, !remarks.isEmpty {
                Section("remarks") {
                    Text(remarks)
                }
            }

            Section {
            } header: {
                VStack {
                    MangaCoverView(coverUrl: mangaData?.cover ?? manga.cover, plugin: plugin)
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)
                        .padding(.horizontal)

                    Text(mangaData?.title ?? manga.title ?? mangaData?.id ?? manga.id)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .padding(.top, 12)
                        .foregroundColor(.primary)

                    if let authors = mangaData?.authors,
                        !authors.isEmpty
                    {
                        HStack(spacing: 4) {
                            HStack(spacing: 4) {
                                ForEach(authors, id: \.self) { author in
                                    Button(action: {
                                        searchQuery = author
                                        showPluginSearchScreen = true
                                    }) {
                                        Text(author)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Image(systemName: "chevron.right")
                                .foregroundColor(.primary.opacity(0.7))
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                }
                .textCase(.none)
            }
            .listRowInsets(EdgeInsets())
            .padding(.top)

            Section {
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        if let updatedAt = mangaData?.updatedAt {
                            Text(updatedAt.formatted(date: .abbreviated, time: .omitted))
                            Text("•")
                        }

                        if let chapters = mangaData?.chapters {
                            Text("\(chapters.flatMap(\.chapters).count) chapters")
                        }

                        if let status = mangaData?.status {
                            Text("•")
                            Text(status.statusText)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button(action: handleReadContinueAction) {
                            HStack {
                                Image(systemName: "book.pages.fill")
                                Text(record != nil ? "continue" : "read")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)

                        Button(action: handleBookmarkAction) {
                            HStack {
                                Image(
                                    systemName: saved != nil
                                        ? "bookmark.slash.fill" : "bookmark.fill"
                                )
                                Text(saved != nil ? "remove" : "bookmark")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(saved != nil ? nil : .accent)
                        .frame(maxWidth: .infinity)
                    }

                    if let record = record {
                        HStack(spacing: 4) {
                            Text("lastRead")

                            if let chapterTitle = record.chapterTitle {
                                Text("•")
                                Text(chapterTitle)
                                    .lineLimit(1)
                            } else {
                                Text("•")
                                Text("chapter \(record.chapterId)")
                                    .lineLimit(1)
                            }

                            Text("•")
                            Text("page \((record.page + 1).description)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Spacer(minLength: 0)
            }

            if let description = mangaData?.description {
                Section {
                    Text(description)
                } header: {
                    Text("description")
                        .padding(.top)
                }
            }

            if let genres = mangaData?.genres,
                !genres.isEmpty
            {
                Section {
                    WrappingHStack(genres, id: \.self, lineSpacing: 8) { genre in
                        Button(action: {
                            selectedGenre = genre
                            showPluginLibraryScreen = true
                        }) {
                            Text(LocalizedStringKey(genre.rawValue))
                                .genreTagStyle()
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding()
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text("genres")
                        .padding(.top)
                }
            }

            if let mangaData = mangaData,
                !mangaData.chapters.isEmpty
            {
                Section {
                    ForEach(Array(mangaData.chapters.enumerated()), id: \.offset) {
                        groupIndex, group in
                        Button(action: {
                            selectedChapterGroupIndex = groupIndex
                            showingChaptersModal = horizontalSizeClass == .compact
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(LocalizedStringKey(group.title))
                                            .foregroundColor(.primary)

                                        Text("\(group.chapters.count) chapters")
                                            .smallTagStyle()
                                    }

                                    if let latestChapter = group.chapters.last {
                                        HStack(spacing: 4) {
                                            Text("latest")
                                                .font(.caption)
                                                .foregroundColor(.primary)

                                            Text(latestChapter.title ?? latestChapter.id)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }

                                Spacer()

                                Image(systemName: "list.bullet")
                                    .foregroundColor(.secondary)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("chapters")
                        .padding(.top)
                }
            }
        }
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                HStack(spacing: 0) {
                    info
                        .frame(maxWidth: 400)

                    if let selectedChapterGroup {
                        let chapters = selectedChapterGroup.chapters
                        ScrollViewReader { proxy in
                            List {
                                Section {
                                    if chapters.isEmpty {
                                        Text("noChaptersAvailable")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(
                                            isReversed ? chapters.reversed() : chapters, id: \.id
                                        ) {
                                            chapter in
                                            Button(action: {
                                                navigateToChapter(chapter)
                                            }) {
                                                HStack {
                                                    Text(chapter.title ?? chapter.id)
                                                        .foregroundColor(.primary)

                                                    if downloadedChapterIds?.contains(chapter.id)
                                                        == true
                                                    {
                                                        Image(systemName: "network.slash")
                                                            .foregroundColor(.secondary)
                                                    }

                                                    if let record = record,
                                                        record.chapterId == chapter.id
                                                    {
                                                        Image(systemName: "clock.arrow.circlepath")
                                                            .foregroundColor(.accentColor)
                                                    }

                                                    Spacer()
                                                    Image(
                                                        systemName: (chapter.locked ?? false)
                                                            ? "lock.fill" : "chevron.right"
                                                    )
                                                    .foregroundColor(.secondary)
                                                }
                                            }
                                            .disabled(chapter.locked ?? false)
                                        }
                                    }

                                } header: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(LocalizedStringKey(selectedChapterGroup.title))
                                            Text("\(chapters.count) chapters")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        HStack {
                                            Button(action: {
                                                isReversed.toggle()
                                            }) {
                                                Image(
                                                    systemName: isReversed
                                                        ? "arrow.up"
                                                        : "arrow.down"
                                                )
                                                .font(.headline)
                                            }
                                            .buttonStyle(.plain)

                                            if plugin is Editable,
                                                detailedManga?.editable ?? true
                                            {
                                                Button(action: {
                                                    isUpdateChaptersModalPresented = true
                                                }) {
                                                    Image(systemName: "pencil")
                                                        .font(.headline)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .onAppear {
                                scrollToRecord(proxy: proxy)
                            }
                            .onChange(of: record, initial: false) { _, _ in
                                scrollToRecord(proxy: proxy)
                            }
                            .onChange(of: selectedChapterGroupIndex) {
                                if let record = record {
                                    proxy.scrollTo(record.chapterId, anchor: .center)
                                }
                            }
                        }
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemGroupedBackground))
                    }
                }
            } else {
                info
            }
        }
        .listSectionSpacing(0)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(mangaData?.title ?? manga.title ?? mangaData?.id ?? manga.id)
        .sheet(isPresented: $showingChaptersModal) {
            [mangaData, selectedChapterGroupIndex] in
            if let mangaData = mangaData,
                let selectedChapterGroupIndex = selectedChapterGroupIndex
            {
                ChaptersModal(
                    plugin: plugin,
                    manga: mangaData,
                    chapterGroupIndex: selectedChapterGroupIndex,
                    record: record,
                    downloadChapters: downloadedChapterIds,
                    onNavigateToChapter: navigateToChapter
                )
            }
        }
        .sheet(isPresented: $isUpdateMangaModalPresented) { [detailedManga] in
            if let detailedManga = detailedManga,
                detailedManga.editable ?? true,
                let editablePlugin = plugin as? any Editable
            {
                UpdateMangaModal(plugin: editablePlugin, manga: detailedManga)
            }
        }
        .sheet(isPresented: $isUpdateChaptersModalPresented) {
            [detailedManga, selectedChapterGroupIndex] in
            if let detailedManga = detailedManga,
                detailedManga.editable ?? true,
                let selectedChapterGroupIndex = selectedChapterGroupIndex,
                let editablePlugin = plugin as? any Editable
            {
                UpdateChaptersModal(
                    plugin: editablePlugin,
                    manga: detailedManga,
                    chapterGroupIndex: selectedChapterGroupIndex,
                    isRootOfSheet: true
                )
            }
        }
        .sheet(isPresented: $isSelectChaptersModalPresented) { [detailedManga] in
            if let detailedManga = detailedManga {
                SelectChaptersModal(
                    plugin: plugin,
                    detailedManga: detailedManga,
                    alreadyDownloaded: downloadedChapterIds,
                    downloadChapters: { chapters in
                        Task {
                            do {
                                _ = try await DownloadService.shared.queue(
                                    plugin: plugin,
                                    manga: detailedManga,
                                    chapters: chapters
                                )
                            } catch {
                                Logger.ui.error("Failed to queue download", error: error)
                            }
                        }
                    }
                )
            }
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
        .navigationDestination(isPresented: $showPluginLibraryScreen) {
            if let selectedGenre = selectedGenre {
                PluginLibraryScreen(plugin: plugin, selectedGenre: selectedGenre)
            }
        }
        .navigationDestination(isPresented: $showPluginSearchScreen) {
            if let searchQuery = searchQuery {
                PluginSearchScreen(plugin: plugin, query: searchQuery)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text(mangaData?.title ?? manga.title ?? mangaData?.id ?? manga.id)
                        .font(.headline)
                    Text(plugin.name ?? plugin.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if plugin.canDownload, mangaData == nil || detailedManga != nil {
                    Button(action: { isSelectChaptersModalPresented = true }) {
                        Image(systemName: "arrow.down.circle")
                    }
                }

                if plugin is Editable, detailedManga?.editable ?? true {
                    Button(action: { isUpdateMangaModalPresented = true }) {
                        Image(systemName: "pencil.circle")
                    }
                }
            }
        }
        .onAppear {
            loadDetailedManga()
            updateRecord()
            updateSaved()
        }
        .onReceive(plugin.objectWillChange) {
            loadDetailedManga()
        }
        .onReceive(DownloadPlugin.shared.objectWillChange) {
            loadDetailedManga()
        }
        .onReceive(SavedService.shared.objectWillChange) {
            updateSaved()
        }
        .onReceive(HistoryService.shared.objectWillChange) {
            updateRecord()
        }
        .apply {
            if horizontalSizeClass == .regular {
                $0.toolbarBackground(.visible, for: .navigationBar)
            } else {
                $0
            }
        }
    }

    private func loadDetailedManga() {
        Task {
            var cachedError: Error?

            do {
                detailedManga = try await plugin.getDetailedManga(manga.id)
                selectedChapterGroupIndex = detailedManga!.chapters.isEmpty ? nil : 0
            } catch {
                detailedManga = nil

                // If the plugin is editable, there is a high chance that it is deleted
                if !(plugin is Editable) {
                    Logger.ui.error("Failed to load detailed manga", error: error)
                    cachedError = error
                }
            }

            do {
                downloadManga = try await DownloadPlugin.shared.getDetailedManga(downloadMangaId)
                if detailedManga == nil {
                    selectedChapterGroupIndex = downloadManga!.chapters.isEmpty ? nil : 0
                }

                downloadedChapterIds = Set(
                    downloadManga!.chapters.flatMap { group in
                        group.chapters.filter { !($0.locked ?? false) }.map(\.id)
                    }
                )
            } catch {
                if detailedManga == nil {
                    Logger.ui.error("Failed to load detailed manga", error: error)
                    cachedError = error
                }
            }

            if mangaData == nil, let cachedError = cachedError {
                let message = String(localized: "failedToLoadMangaDetails")
                NotificationService.shared.showError(
                    String(format: message, cachedError.localizedDescription))

                dismiss()
            }
        }
    }
}
