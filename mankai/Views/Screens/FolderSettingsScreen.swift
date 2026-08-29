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
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddFolderModal = true
                } label: {
                    Image(systemName: "plus.circle")
                }
            }
        }
        .navigationTitle("folders").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddFolderModal) { AddBrowsableFolderModal() }
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
