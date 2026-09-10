//
//  DebugGetMangas.swift
//  mankai
//
//  Created by Travis XU on 10/9/2026.
//

import SwiftUI

struct DebugGetMangas: View {
    let mangaIds: [String]
    let plugin: JsPlugin

    @State var mangas: [Manga]? = nil

    var body: some View {
        Group {
            if !plugin.supports(.batchMangas) {
                DebugMethodNotSupported()
            } else if let mangas = mangas {
                List { DebugMangas(mangas: mangas, plugin: plugin, showsMethodPicker: false) }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard plugin.supports(.batchMangas) else { return }
            mangas = try! await plugin.getMangas(mangaIds)
            Logger.jsPlugin.debug("mangas: \(mangas as Any)")
        }
        .navigationTitle(Text(verbatim: "getMangas"))
    }
}
