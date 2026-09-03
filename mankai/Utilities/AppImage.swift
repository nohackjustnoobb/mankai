//
//  AppImage.swift
//  mankai
//
//  Created by Travis XU on 10/8/2026.
//

import Combine
import CoreImage
import UIKit

/// A reader image that displays its source immediately, then publishes a processed replacement.
final class AppImage: ObservableObject {
    enum SlideEdge {
        case left
        case right
    }

    private static let sourceSlideWidth = SmartGrouping.inputSize.width
    private static let outputSlideSize = CGSize(
        width: SmartGrouping.inputSize.width / 2, height: SmartGrouping.inputSize.height)
    private static let upscalingTileContext = 16

    @Published private(set) var image: UIImage
    @Published private(set) var isProcessingFinished = false

    private var processingTask: Task<UIImage?, Never>?
    private var slideTask: Task<(left: CIImage, right: CIImage)?, Never>?
    private var leftSlide: CIImage?
    private var rightSlide: CIImage?

    var size: CGSize { image.size }

    init?(data: Data) {
        guard let image = UIImage(data: data) else { return nil }
        self.image = image

        slideTask = Task.detached(priority: .utility) {
            guard !Task.isCancelled,
                let image = CIImage(data: data, options: [.applyOrientationProperty: true])
            else { return nil }

            return Self.makeSlides(from: image)
        }

        let processingTask: Task<UIImage?, Never> = Task.detached(priority: .utility) {
            let processors = await Self.makeProcessors()
            guard !processors.isEmpty,
                var processedImage = CIImage(data: data, options: [.applyOrientationProperty: true])
            else { return nil }

            do {
                for processor in processors {
                    processedImage = try await processor.process(image: processedImage)
                    try Task.checkCancellation()
                }
            } catch is CancellationError { return nil } catch {
                Logger.ui.error("Failed to process reader image", error: error)
                return nil
            }

            return UIImage(ciImage: processedImage)
        }
        self.processingTask = processingTask

        Task { @MainActor [weak self] in
            let processedImage = await processingTask.value
            guard !processingTask.isCancelled, let self else { return }

            if let processedImage { self.image = processedImage }
            isProcessingFinished = true
        }
    }

    /// Returns one generated edge slide and releases the stored reference immediately.
    /// Each edge can only be read once.
    @MainActor func takeSlide(_ edge: SlideEdge) async -> CIImage? {
        if let slideTask {
            if let slides = await slideTask.value {
                leftSlide = slides.left
                rightSlide = slides.right
            }
            self.slideTask = nil
        }

        switch edge { case .left:
            defer { leftSlide = nil }
            return leftSlide
            case .right:
                defer { rightSlide = nil }
                return rightSlide
        }
    }

    @MainActor func releaseSlides() {
        slideTask?.cancel()
        slideTask = nil
        leftSlide = nil
        rightSlide = nil
    }

    deinit {
        processingTask?.cancel()
        slideTask?.cancel()
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

    @MainActor private static func makeProcessors() -> [any ImageProcessor] {
        let shouldUpscale =
            (UserDefaults.standard.object(forKey: SettingsKey.animeSharpUpscaling.rawValue) as? Bool)
            ?? SettingsDefaults.animeSharpUpscaling
        let shouldDownsample =
            (UserDefaults.standard.object(forKey: SettingsKey.downsampleImages.rawValue) as? Bool)
            ?? SettingsDefaults.downsampleImages
        let pointSize = UIApplication.windowBounds.size

        var processors: [any ImageProcessor] = []

        if shouldUpscale {
            processors.append(
                UpscalingImageProcessor(context: upscalingTileContext, pointSize: pointSize))
        }

        if shouldDownsample { processors.append(DownsampleImageProcessor(pointSize: pointSize)) }

        return processors
    }

}
