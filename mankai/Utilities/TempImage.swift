//
//  TempImage.swift
//  mankai
//
//  Created by Travis XU on 10/8/2026.
//

import CoreImage
import ImageIO
import UIKit

/// A temporary workaround that avoids retaining encoded image data longer than necessary.
///
/// Every conversion requires the caller to explicitly decide whether the source data
/// will be reused. The decoded `UIImage` is cached because the UI may request it again.
final class TempImage {
    private var data: Data?
    private var cachedUIImage: UIImage?
    private var cachedCIImage: CIImage?

    var hasAnalysisSource: Bool {
        data != nil || cachedCIImage != nil
    }

    var size: CGSize {
        cachedUIImage?.size ?? .zero
    }

    init(data: Data) {
        self.data = data
    }

    func uiImage(
        downsampledTo pointSize: CGSize? = nil,
        scale: CGFloat = UIScreen.main.scale,
        retainData: Bool
    ) -> UIImage? {
        if let cachedUIImage {
            releaseDataIfNeeded(retainData: retainData)
            return cachedUIImage
        }

        guard let data else { return nil }

        let image: UIImage?
        if let pointSize {
            image = Self.downsample(data: data, to: pointSize, scale: scale)
        } else {
            image = UIImage(data: data)
        }

        guard let image else { return nil }

        cachedUIImage = image
        releaseDataIfNeeded(retainData: retainData)
        return image
    }

    func ciImage(retainData: Bool) -> CIImage? {
        if let cachedCIImage {
            releaseDataIfNeeded(retainData: retainData)
            return cachedCIImage
        }

        guard let data else { return nil }

        guard
            let image = CIImage(
                data: data,
                options: [.applyOrientationProperty: true]
            )
        else {
            return nil
        }

        cachedCIImage = image
        self.data = nil
        releaseDataIfNeeded(retainData: retainData)
        return image
    }

    func releaseData() {
        data = nil
        cachedCIImage = nil
    }

    func restoreSourceData(_ data: Data) {
        guard !hasAnalysisSource else { return }
        self.data = data
    }

    private func releaseDataIfNeeded(retainData: Bool) {
        if !retainData {
            releaseData()
        }
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

        let maxPixelSize = Swift.max(pointSize.width, pointSize.height) * 2
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
