//
//  AppImage.swift
//  mankai
//
//  Created by Travis XU on 10/8/2026.
//

import CoreImage
import ImageIO
import UIKit

final class AppImage {
    private var data: Data?
    private let embeddingTask: Task<ImageEdgeEmbeddings?, Never>?
    private var cachedUIImage: UIImage?

    var size: CGSize {
        uiImage()?.size ?? .zero
    }

    init(data: Data, generateEmbedding: Bool) {
        self.data = data
        embeddingTask =
            generateEmbedding
            ? Task.detached(priority: .utility) {
                guard
                    !Task.isCancelled,
                    let image = CIImage(
                        data: data,
                        options: [.applyOrientationProperty: true]
                    )
                else {
                    return nil
                }

                return try? await EncoderWrapper.shared.predict(image: image)
            }
            : nil
    }

    func uiImage() -> UIImage? {
        if let cachedUIImage {
            return cachedUIImage
        }

        guard let data else {
            return nil
        }

        let shouldDownsample =
            (UserDefaults.standard.object(
                forKey: SettingsKey.downsampleImages.rawValue
            ) as? Bool) ?? SettingsDefaults.downsampleImages

        let image =
            shouldDownsample
            ? Self.downsample(
                data: data,
                to: UIApplication.windowBounds.size,
                scale: UIScreen.main.scale
            )
            : UIImage(data: data)

        if image != nil {
            cachedUIImage = image
            self.data = nil
        }
        return image
    }

    func imageEmbedding() async -> ImageEdgeEmbeddings? {
        await embeddingTask?.value
    }

    private static func downsample(
        data: Data,
        to pointSize: CGSize,
        scale: CGFloat
    ) -> UIImage? {
        guard pointSize.width.isFinite,
            pointSize.height.isFinite,
            pointSize.width > 0,
            pointSize.height > 0,
            scale.isFinite,
            scale > 0
        else {
            return nil
        }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let maxPixelSize = Swift.max(pointSize.width, pointSize.height) * scale
        let thumbnailOptions =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}
