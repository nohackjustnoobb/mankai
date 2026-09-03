//
//  ImageProcessor.swift
//  mankai
//
//  Created by Travis XU on 3/9/2026.
//

import CoreImage

protocol ImageProcessor: Sendable {
    /// Applies this processor's operation to the current pipeline image.
    func process(image: CIImage) async throws -> CIImage
}

struct DownsampleImageProcessor: ImageProcessor {
    let pointSize: CGSize

    func process(image: CIImage) async throws -> CIImage {
        guard let maxPixelSize = Self.maxPixelSize(for: pointSize) else { return image }
        let sourceMaxPixelSize = Swift.max(image.extent.width, image.extent.height)
        guard sourceMaxPixelSize.isFinite, sourceMaxPixelSize > maxPixelSize else { return image }

        let scale = maxPixelSize / sourceMaxPixelSize
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    static func maxPixelSize(for pointSize: CGSize) -> CGFloat? {
        guard pointSize.width.isFinite, pointSize.height.isFinite, pointSize.width > 0,
            pointSize.height > 0
        else { return nil }

        // Intentional set to 2 to make the downsample effect more significant.
        return Swift.max(pointSize.width, pointSize.height) * 2
    }
}

struct UpscalingImageProcessor: ImageProcessor {
    let context: Int
    let pointSize: CGSize

    func process(image: CIImage) async throws -> CIImage {
        guard let maxPixelSize = DownsampleImageProcessor.maxPixelSize(for: pointSize) else {
            return image
        }

        let sourceMaxPixelSize = Swift.max(image.extent.width, image.extent.height)
        guard sourceMaxPixelSize.isFinite, sourceMaxPixelSize > 0, sourceMaxPixelSize < maxPixelSize
        else { return image }

        return try await Upscaling.shared.upscale(image, context: context)
    }
}
