//
//  DebugIsOnline.swift
//  mankai
//
//  Created by Travis XU on 10/9/2026.
//

import SwiftUI

struct DebugIsOnline: View {
    let plugin: JsPlugin

    @State var isOnline: Bool? = nil

    var body: some View {
        Group {
            if !plugin.supports(.onlineCheck) {
                DebugMethodNotSupported()
            } else if let isOnline = isOnline {
                List {
                    Section {
                        LabeledContent {
                            Text(String(describing: isOnline))
                        } label: {
                            Text(verbatim: "isOnline")
                        }
                    } header: {
                        Text(verbatim: "isOnline")
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard plugin.supports(.onlineCheck) else { return }
            isOnline = try! await plugin.isOnline()
            Logger.jsPlugin.debug("isOnline: \(isOnline as Any)")
        }
        .navigationTitle(Text(verbatim: "isOnline"))
    }
}
