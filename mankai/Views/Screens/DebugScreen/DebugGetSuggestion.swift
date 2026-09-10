//
//  DebugGetSuggestion.swift
//  mankai
//
//  Created by Travis XU on 10/9/2026.
//

import SwiftUI

struct DebugGetSuggestion: View {
    let plugin: JsPlugin

    @State var suggestions: [String]? = nil

    var body: some View {
        Group {
            if !plugin.supports(.suggestions) {
                DebugMethodNotSupported()
            } else if let suggestions = suggestions {
                List {
                    Section("suggestions") {
                        ForEach(suggestions, id: \.self) { suggestion in Text(suggestion) }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard plugin.supports(.suggestions) else { return }
            suggestions = try! await plugin.getSuggestions("mankai")
            Logger.jsPlugin.debug("suggestions: \(suggestions as Any)")
        }
        .navigationTitle(Text(verbatim: "getSuggestion"))
    }
}
