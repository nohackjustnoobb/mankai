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
        .onOpenURL { url in
            Logger.ui.info("Received URL: \(url)")
            selectedTab = .browse
            importedFiles = [url]
        }
    }
}
