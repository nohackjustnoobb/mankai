//
//  BrowseTab.swift
//  mankai
//
//  Created by Travis XU on 14/7/2026.
//

import SwiftUI

struct BrowseTab: View {
    @ObservedObject private var browseService = BrowseService.shared

    var body: some View {
        NavigationStack {
            List(browseService.plugins, id: \.id) { plugin in
                NavigationLink {
                    BrowseScreen(plugin: plugin)
                } label: {
                    HStack(spacing: 12) {
                        if let image = plugin.systemImageName {
                            Image(systemName: image)
                                .foregroundStyle(.tint)
                        }
                        Text(plugin.name ?? plugin.id)
                    }
                }
            }
            .navigationTitle("browse")
        }
    }
}
