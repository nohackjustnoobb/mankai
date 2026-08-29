//
//  DebugGetImage.swift
//  mankai
//
//  Created by Travis XU on 26/6/2025.
//

import SwiftUI

struct DebugGetImage: View {
    let plugin: JsPlugin
    let url: String

    @State var imageData: Data? = nil

    var body: some View {
        Group {
            if let imageData = imageData {
                List {
                    if let uiImage = UIImage(data: imageData) {
                        Section("image") {
                            VStack {
                                Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fit)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        Section("details") {
                            HStack {
                                Text("imageSize")
                                Spacer()
                                Text(
                                    String(
                                        format: String(localized: "byteCountFormat"),
                                        imageData.count)
                                )
                                .foregroundColor(.secondary)
                            }
                            HStack {
                                Text("url")
                                Spacer()
                                Text(url).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                    } else {
                        Section("error") {
                            VStack {
                                Text("failedToLoadImage").font(.headline)
                                Text(
                                    String(
                                        format: String(localized: "dataSizeMessageFormat"),
                                        imageData.count)
                                )
                                .font(.caption).foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity).padding()
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard plugin.supports(.image) else { return }
            imageData = try! await plugin.getImage(url)
            Logger.jsPlugin.debug("imageData count: \(imageData?.count ?? 0)")
        }
    }
}
