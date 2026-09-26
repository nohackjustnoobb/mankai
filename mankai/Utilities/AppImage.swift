//
//  AppImage.swift
//  mankai
//
//  Created by Travis XU on 10/8/2026.
//

import Combine
import CoreImage
import UIKit

/// A reader image that publishes a processed replacement when needed.
@MainActor final class AppImage: ObservableObject {
    enum SlideEdge {
        case left
        case right
    }

    nonisolated private static let sourceSlideWidth = SmartGrouping.inputSize.width
    nonisolated private static let outputSlideSize = CGSize(
        width: SmartGrouping.inputSize.width / 2, height: SmartGrouping.inputSize.height)

    @Published private(set) var image: UIImage
    @Published private(set) var isProcessingFinished = false

    private var processingTask: Task<UIImage?, Never>?
    private var slideTask: Task<(left: CIImage, right: CIImage)?, Never>?
    private var leftSlide: CIImage?
    private var rightSlide: CIImage?

    var size: CGSize { image.size }

    static func load(data: Data) async -> AppImage? {
        guard let prepared = await ImageProcessingService.shared.load(data: data) else {
            return nil
        }
        return AppImage(image: prepared.image, data: data, processingTask: prepared.processingTask)
    }

    private init(image: UIImage, data: Data, processingTask: Task<UIImage?, Never>?) {
        self.image = image
        self.processingTask = processingTask
        isProcessingFinished = processingTask == nil

        slideTask = Task.detached(priority: .utility) {
            guard !Task.isCancelled,
                let image = CIImage(data: data, options: [.applyOrientationProperty: true])
            else { return nil }

            return Self.makeSlides(from: image)
        }

        if let processingTask {
            Task { @MainActor [weak self] in
                let processedImage = await processingTask.value
                guard !processingTask.isCancelled, let self else { return }

                if let processedImage { self.image = processedImage }
                isProcessingFinished = true
            }
        }
    }

    /// Returns one generated edge slide and releases the stored reference immediately.
    /// Each edge can only be read once.
    func takeSlide(_ edge: SlideEdge) async -> CIImage? {
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

    func releaseSlides() {
        slideTask?.cancel()
        slideTask = nil
        leftSlide = nil
        rightSlide = nil
    }

    isolated deinit {
        processingTask?.cancel()
        slideTask?.cancel()
    }

    nonisolated private static func makeSlides(from image: CIImage) -> (
        left: CIImage, right: CIImage
    )? {
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

    nonisolated private static func resizeSlide(_ image: CIImage) -> CIImage {
        let scaleX = outputSlideSize.width / image.extent.width
        let scaleY = outputSlideSize.height / image.extent.height

        return image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: CGRect(origin: .zero, size: outputSlideSize))
    }

}
