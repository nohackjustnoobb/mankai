//
//  MainScreen.swift
//  mankai
//
//  Created by Travis XU on 20/6/2025.
//

import SwiftUI

struct MainScreen: View {
    private enum Tab: Hashable {
        case home, library, browse, settings
    }

    @State private var selectedTab: Tab = .home
    @State private var importedFiles: [URL] = []
    @State private var pluginImportRequest: PluginImportRequest?

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeTab()
                .tag(Tab.home)
                .tabItem {
                    Label("home", systemImage: "house")
                }
            LibraryTab()
                .tag(Tab.library)
                .tabItem {
                    Label("library", systemImage: "books.vertical.fill")
                }
            BrowseTab(importedFiles: $importedFiles)
                .tag(Tab.browse)
                .tabItem {
                    Label("browse", systemImage: "folder.fill")
                }
            SettingsTab()
                .tag(Tab.settings)
                .tabItem {
                    Label("settings", systemImage: "gearshape")
                }
        }
        .overlay(alignment: .bottom) {
            NotificationContainerView()
        }
        .sheet(item: $pluginImportRequest) { request in
            AddPluginsModal(sources: request.sources)
        }
        .onOpenURL { url in
            Logger.ui.info("Received URL: \(url)")

            if url.isFileURL {
                selectedTab = .browse
                importedFiles.append(url)

                return
            }

            if url.scheme?.lowercased() == "mankai", let host = url.host?.lowercased() {
                switch host {
                case "add-plugins":
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

                    let plugins = (components?.queryItems ?? []).compactMap {
                        item -> PluginImportSource? in
                        guard
                            let type = PluginImportSource.Kind(
                                rawValue: item.name.lowercased()
                            ), let value = item.value, let decodedURL = Base62.decode(value),
                            let pluginURL = URL(string: decodedURL)
                        else {
                            return nil
                        }

                        return PluginImportSource(kind: type, url: pluginURL)
                    }

                    guard !plugins.isEmpty else {
                        Logger.ui.warning("No supported plugins found in URL: \(url)")
                        return
                    }

                    pluginImportRequest = PluginImportRequest(sources: plugins)
                default:
                    Logger.ui.warning("Unsupported host: \(host)")
                }
            }
        }
    }
}
