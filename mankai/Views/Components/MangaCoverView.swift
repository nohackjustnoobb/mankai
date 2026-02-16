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

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image = image {
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }

            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGray6))
            } else {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGray6))
            }

            if let tag = tag, !tag.isEmpty {
                Text(tag)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 8,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 8,
                            topTrailingRadius: 0
                        )
                        .fill(tagColor ?? .green.opacity(0.8))
                    )
            }
        }
        .onAppear {
            loadImage()
        }
    }

    private func loadImage() {
        guard let coverUrl = coverUrl,
              let plugin = plugin,
              image == nil
        else {
            return
        }

        isLoading = true

        Task {
            do {
                let data = try await plugin.getImage(coverUrl)
                self.image = UIImage(data: data)
                self.isLoading = false
            } catch {
                // try offline
                if let data = try? await DownloadPlugin.shared.getImage(coverUrl) {
                    self.image = UIImage(data: data)
                }

                self.isLoading = false
            }
        }
    }
}
