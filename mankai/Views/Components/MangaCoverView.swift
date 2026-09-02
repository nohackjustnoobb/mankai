//
//  MangaCoverView.swift
//  mankai
//
//  Created by Travis XU on 27/6/2025.
//

import SwiftUI

struct MangaCoverView: View {
    let coverUrl: String?
    let plugin: Plugin?
    var tag: String? = nil
    var tagColor: Color? = nil
    var cornerRadius: CGFloat? = nil

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image = image {
                GeometryReader { proxy in
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                }

            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGray6))
            } else {
                Group {
                    if #available(iOS 18.0, *) {
                        Image(systemName: "photo.badge.exclamationmark")
                    } else {
                        Image(systemName: "exclamationmark.circle.fill")
                    }
                }
                .font(.title2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(.systemGray6))
            }

            if let tag = tag, !tag.isEmpty { tagView(tag) }
        }
        .clipShape(RoundedRectangle(cornerRadius: effectiveCornerRadius)).onAppear { loadImage() }
    }

    @ViewBuilder private func tagView(_ tag: String) -> some View {
        let color = tagColor ?? .green

        if #available(iOS 26.0, *) {
            Text(tag).font(.caption).fontWeight(.semibold).foregroundColor(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .glassEffect(
                    .clear.tint(color), in: RoundedRectangle(cornerRadius: effectiveCornerRadius)
                )
                .padding(effectiveCornerRadius / 4)
        } else {
            Text(tag).font(.caption).fontWeight(.semibold).foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: effectiveCornerRadius, bottomLeadingRadius: 0,
                        bottomTrailingRadius: effectiveCornerRadius, topTrailingRadius: 0
                    )
                    .fill(color.opacity(0.8)))
        }
    }

    private var effectiveCornerRadius: CGFloat {
        if let cornerRadius { return cornerRadius }

        if #available(iOS 26.0, *) { return 12 }

        return 8
    }

    private func loadImage() {
        guard let coverUrl = coverUrl, let plugin = plugin, image == nil else { return }

        isLoading = true

        Task {
            if plugin.supports(.image), let data = try? await plugin.getImage(coverUrl) {
                self.image = AppImage(data: data, generateSlides: false).uiImage()
            } else if let data = try? await DownloadPlugin.shared.getImage(coverUrl) {
                self.image = AppImage(data: data, generateSlides: false).uiImage()
            }

            self.isLoading = false
        }
    }
}
