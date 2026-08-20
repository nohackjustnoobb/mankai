//
//  BrowseTab.swift
//  mankai
//
//  Created by Travis XU on 14/7/2026.
//

import SwiftUI

struct BrowseTab: View {
    @ObservedObject private var browseService = BrowseService.shared
    @Binding var importedFiles: [URL]
    @State private var showingAddFolderModal = false
    @State private var importError: String?
    @State private var pluginPendingDeletion: BrowsablePlugin?
    @State private var showingImportsModal = false
    @State private var importDestinationPluginId: String?
    @State private var editDestinationPluginId: String?

    init(importedFiles: Binding<[URL]>) {
        _importedFiles = importedFiles
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(browseService.plugins, id: \.id) { plugin in
                        NavigationLink {
                            BrowseScreen(plugin: plugin)
                        } label: {
                            Label(
                                plugin.name ?? plugin.id,
                                systemImage: plugin.systemImageName
                            )
                            .labelStyle(ColorfulIconLabelStyle(color: plugin.systemImageColor))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !(plugin is AppDirBrowsablePlugin) {
                                Button(role: .destructive) {
                                    pluginPendingDeletion = plugin
                                } label: {
                                    Label("remove", systemImage: "trash")
                                }

                                Button {
                                    editDestinationPluginId = plugin.id
                                } label: {
                                    Label("edit", systemImage: "pencil")
                                }
                                .tint(.blue)

                            }
                        }
                    }

                    Button {
                        showingAddFolderModal = true
                    } label: {
                        Label(
                            "addFolder",
                            systemImage: "folder.badge.plus"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text("swipeToEditOrRemoveFolder")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingImportsModal = true
                    } label: {
                        Label("imports", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .navigationTitle("browse")
            .alert(
                "failedToAddFolder",
                isPresented: .init(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )
            ) {
                Button("ok", role: .cancel) {}
            } message: {
                if let importError {
                    Text(importError)
                }
            }
            .confirmationDialog(
                "removeFolder",
                isPresented: .init(
                    get: { pluginPendingDeletion != nil },
                    set: { if !$0 { pluginPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("remove", role: .destructive) {
                    if let plugin = pluginPendingDeletion {
                        do {
                            try browseService.removePlugin(plugin.id)
                        } catch {
                            importError = error.localizedDescription
                        }
                        pluginPendingDeletion = nil
                    }
                }
                Button("cancel", role: .cancel) {
                    pluginPendingDeletion = nil
                }
            } message: {
                Text("removeFolderConfirmation")
            }
            .sheet(
                isPresented: .init(
                    get: { showingImportsModal || !importedFiles.isEmpty },
                    set: { _ in
                        showingImportsModal = false
                        importedFiles = []
                    }
                )
            ) {
                ImportsModal(initialFiles: importedFiles) { plugin in
                    importDestinationPluginId = plugin.id
                }
            }
            .sheet(isPresented: $showingAddFolderModal) {
                AddBrowsableFolderModal()
            }
            .navigationDestination(item: $importDestinationPluginId) { pluginId in
                if let plugin = browseService.getImportablePlugin(pluginId) {
                    BrowseScreen(
                        plugin: plugin,
                        entry: plugin.importsEntity
                    )
                }
            }
            .navigationDestination(item: $editDestinationPluginId) { pluginId in
                if let plugin = browseService.plugins.first(where: { $0.id == pluginId }) {
                    FolderInfoScreen(plugin: plugin)
                }
            }
        }
    }
}
