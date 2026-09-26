//
//  FolderSettingsScreen.swift
//  mankai
//
//  Created by Travis XU on 20/8/2026.
//

import SwiftUI

struct FolderSettingsScreen: View {
    @ObservedObject private var browseService = BrowseService.shared
    @State private var showingAddFolderModal = false
    @State private var showingRemoveConfirmation = false
    @State private var folderIdsToRemove: [String] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            SettingsHeaderView(
                image: Image(systemName: "folder.fill"), color: .blue,
                title: String(localized: "folders"),
                description: String(localized: "foldersDescription"))

            ForEach(browseService.plugins, id: \.id) { plugin in
                NavigationLink {
                    FolderInfoScreen(plugin: plugin)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plugin.name ?? plugin.id)

                            HStack(spacing: 8) {
                                Text(folderTypeName(for: plugin)).smallTagStyle()

                                if plugin is AppDirBrowsablePlugin {
                                    Text("builtin").smallTagStyle()
                                }
                            }
                        }
                    } icon: {
                        plugin.icon
                    }
                    .labelStyle(ColorfulIconLabelStyle(color: plugin.color))
                }
                .deleteDisabled(plugin is AppDirBrowsablePlugin)
            }
            .onDelete { offsets in
                let plugins = browseService.plugins
                folderIdsToRemove = offsets.compactMap { index in
                    let plugin = plugins[index]
                    return plugin is AppDirBrowsablePlugin ? nil : plugin.id
                }
                showingRemoveConfirmation = !folderIdsToRemove.isEmpty
            }
        }
        .toolbar {
            if browseService.plugins.contains(where: { !($0 is AppDirBrowsablePlugin) }) {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddFolderModal = true
                } label: {
                    ToolbarIcon(systemName: "plus", legacySystemName: "plus.circle")
                }
            }
        }
        .navigationTitle("folders").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddFolderModal) { AddBrowsableFolderModal() }
        .confirmationDialog(
            "removeFolder", isPresented: $showingRemoveConfirmation, titleVisibility: .visible
        ) {
            Button("remove", role: .destructive) {
                let ids = folderIdsToRemove
                folderIdsToRemove = []
                for id in ids {
                    do { try browseService.removePlugin(id) } catch {
                        errorMessage = error.localizedDescription
                        break
                    }
                }
            }
            Button("cancel", role: .cancel) { folderIdsToRemove = [] }
        } message: {
            if folderIdsToRemove.count == 1 {
                Text("removeFolderConfirmation")
            } else {
                Text("removeFoldersConfirmation")
            }
        }
        .alert(
            "failedToRemovePlugin",
            isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("ok", role: .cancel) { errorMessage = nil }
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
    }
}

private func folderTypeName(for plugin: BrowsablePlugin) -> String {
    switch plugin { case is AppDirBrowsablePlugin, is FsBrowsablePlugin:
        return String(localized: "fs")
        case is SmbBrowsablePlugin: return String(localized: "smb")
        case is NfsBrowsablePlugin: return String(localized: "nfs")
        case is WebDavBrowsablePlugin: return String(localized: "webdav")
        case is OpdsBrowsablePlugin: return String(localized: "opds")
        default: return String(localized: "folder")
    }
}
