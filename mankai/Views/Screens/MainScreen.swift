//
//  MainScreen.swift
//  mankai
//
//  Created by Travis XU on 20/6/2025.
//

import SwiftUI

struct MainScreen: View {
    var body: some View {
        TabView {
            HomeTab()
                .tabItem {
                    Label("home", systemImage: "house")
                }
            LibraryTab()
                .tabItem {
                    Label("library", systemImage: "books.vertical.fill")
                }
            BrowseTab()
                .tabItem {
                    Label("browse", systemImage: "folder.fill")
                }
            SettingsTab()
                .tabItem {
                    Label("settings", systemImage: "gearshape")
                }
          
        }
        .overlay(alignment: .bottom) {
            NotificationContainerView()
        }
    }
}
