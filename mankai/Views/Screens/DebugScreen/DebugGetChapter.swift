//
//  DebugGetChapter.swift
//  mankai
//
//  Created by Travis XU on 26/6/2025.
//

import SwiftUI

struct DebugGetChapter: View {
    let plugin: JsPlugin
    let manga: DetailedManga
    let chapter: Chapter

    @State var urls: [String]?

    var body: some View {
        Group {
            if let urls = urls {
                List {
                    Section("urls") {
                        ForEach(urls, id: \.self) { url in
                            if plugin.supports(.image) {
                                NavigationLink(destination: {
                                    DebugGetImage(plugin: plugin, url: url)
                                }) {
                                    Text(url)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            } else {
                                Text(url)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard plugin.supports(.chapter) else {
                urls = []
                return
            }
            urls = try! await plugin.getChapter(manga: manga, chapter: chapter)
            Logger.jsPlugin.debug("urls: \(urls ?? [])")
        }
    }
}
