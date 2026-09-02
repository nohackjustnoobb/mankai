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
    enum SlideEdge {
        case left
        case right
    }

    private static let sourceSlideWidth = AdjacencyModelWrapper.inputSize.width
    private static let outputSlideSize = CGSize(
        width: AdjacencyModelWrapper.inputSize.width / 2,
        height: AdjacencyModelWrapper.inputSize.height)

    private var data: Data?
    private var cachedUIImage: UIImage?
    private var leftSlide: CIImage?
    private var rightSlide: CIImage?

    var size: CGSize { uiImage()?.size ?? .zero }

    init(data: Data, generateSlides: Bool) {
        self.data = data

        guard generateSlides,
            let image = CIImage(data: data, options: [.applyOrientationProperty: true]),
            let slides = Self.makeSlides(from: image)
        else { return }

        leftSlide = slides.left
        rightSlide = slides.right
    }

    func uiImage() -> UIImage? {
        if let cachedUIImage { return cachedUIImage }
        guard let data else { return nil }

        let shouldDownsample =
            (UserDefaults.standard.object(forKey: SettingsKey.downsampleImages.rawValue) as? Bool)
            ?? SettingsDefaults.downsampleImages

        let image =
            shouldDownsample
            ? Self.downsample(
                data: data, to: UIApplication.windowBounds.size, scale: UIScreen.main.scale)
            : UIImage(data: data)

        if let image {
            cachedUIImage = image
            self.data = nil
        }

        return image
    }

    /// Returns one generated edge slide and releases the stored reference immediately.
    /// Each edge can only be read once.
    func takeSlide(_ edge: SlideEdge) -> CIImage? {
        switch edge { case .left:
            defer { leftSlide = nil }
            return leftSlide
            case .right:
                defer { rightSlide = nil }
                return rightSlide
        }
    }

    func releaseSlides() {
        leftSlide = nil
        rightSlide = nil
    }

    private static func makeSlides(from image: CIImage) -> (left: CIImage, right: CIImage)? {
        let extent = image.extent.standardized
        guard extent.width.isFinite, extent.height.isFinite, extent.width > 0, extent.height > 0
        else { return nil }

        let imageAtOrigin = image.cropped(to: extent)
            .transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))

        let slideWidth = min(sourceSlideWidth, extent.width)
        let leftSlide = imageAtOrigin.cropped(
            to: CGRect(x: 0, y: 0, width: slideWidth, height: extent.height))

        let rightOriginX = max(0, extent.width - sourceSlideWidth)
        let rightSlide =
            imageAtOrigin.cropped(
                to: CGRect(x: rightOriginX, y: 0, width: slideWidth, height: extent.height)
            )
            .transformed(by: CGAffineTransform(translationX: -rightOriginX, y: 0))

        return (left: resizeSlide(leftSlide), right: resizeSlide(rightSlide))
    }

    private static func resizeSlide(_ image: CIImage) -> CIImage {
        let scaleX = outputSlideSize.width / image.extent.width
        let scaleY = outputSlideSize.height / image.extent.height

        return image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: CGRect(origin: .zero, size: outputSlideSize))
    }

    private static func downsample(data: Data, to pointSize: CGSize, scale: CGFloat) -> UIImage? {
        guard pointSize.width.isFinite, pointSize.height.isFinite, pointSize.width > 0,
            pointSize.height > 0, scale.isFinite, scale > 0
        else { return nil }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        // Intentional set to 2 to make the downsample effect more significant
        let maxPixelSize = Swift.max(pointSize.width, pointSize.height) * 2
        let thumbnailOptions =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}
