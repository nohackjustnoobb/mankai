//
//  DebugSearchAndGetSuggestionAndIsOnline.swift
//  mankai
//
//  Created by Travis XU on 26/6/2025.
//

import SwiftUI

struct DebugSearchAndGetSuggestionAndIsOnline: View {
    let plugin: JsPlugin

    @State var isOnline: Bool? = nil
    @State var suggestions: [String]? = nil
    @State var mangas: [Manga]? = nil

    var body: some View {
        Group {
            if mangas == nil && suggestions == nil && isOnline == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if let isOnline = isOnline {
                        Section("isOnline") {
                            LabeledContent("isOnline") { Text(String(describing: isOnline)) }
                        }
                    }

                    if let suggestions = suggestions {
                        Section("suggestions") {
                            ForEach(suggestions, id: \.self) { item in Text(item) }
                        }
                    }

                    if let mangas = mangas { DebugMangas(mangas: mangas, plugin: plugin) }
                }
            }
        }
        .task {
            if plugin.supports(.onlineCheck) {
                isOnline = try! await plugin.isOnline()
                Logger.jsPlugin.debug("isOnline: \(isOnline as Any)")
            }

            if plugin.supports(.search), plugin.supports(.suggestions) {
                suggestions = try! await plugin.getSuggestions("mankai")
                Logger.jsPlugin.debug("suggestions: \(suggestions as Any)")
            }

            if plugin.supportsSearch() {
                mangas = try! await plugin.search(
                    "mankai", page: 1, genre: .all, status: .any, isAuthor: false)
                Logger.jsPlugin.debug("mangas: \(mangas as Any)")
            }
        }
        .navigationTitle("getList")
    }
}
