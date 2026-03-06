//
//  SettingsTab.swift
//  mankai
//
//  Created by Travis XU on 21/6/2025.
//

import SwiftUI

struct SettingsTab: View {
    @AppStorage(SettingsKey.showDebugScreen.rawValue) private var showDebugScreen: Bool =
        SettingsDefaults.showDebugScreen

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(
                        destination: GeneralSettingsScreen()
                    ) {
                        Label("general", systemImage: "gear")
                            .labelStyle(ColorfulIconLabelStyle(color: .gray))
                    }

                    NavigationLink(
                        destination: ReaderSettingsScreen()
                    ) {
                        Label("reader", systemImage: "book.pages.fill")
                            .labelStyle(ColorfulIconLabelStyle(color: .orange))
                    }

                    NavigationLink(
                        destination: PluginSettingsScreen()
                    ) {
                        Label("plugins", systemImage: "puzzlepiece.extension.fill")
                            .labelStyle(ColorfulIconLabelStyle(color: .red, imageScale: .small))
                    }
                }

                Section {
                    NavigationLink(
                        destination: HistoryScreen()
                    ) {
                        Label(
                            "history",
                            systemImage: "clock.arrow.circlepath"
                        )
                        .labelStyle(ColorfulIconLabelStyle(color: .indigo))
                    }

                    NavigationLink(
                        destination: SyncSettingsScreen()
                    ) {
                        Label(
                            "sync",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        .labelStyle(ColorfulIconLabelStyle(color: .blue))
                    }
                }

                if showDebugScreen {
                    Section {
                        NavigationLink(
                            destination: DebugScreen()
                        ) {
                            Label("debug", systemImage: "curlybraces")
                                .labelStyle(ColorfulIconLabelStyle(color: .yellow))
                        }
                    }
                }
            }
            .navigationTitle("settings")
        }
    }
}
