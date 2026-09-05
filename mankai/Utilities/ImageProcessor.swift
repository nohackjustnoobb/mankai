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

extension ImageProcessor {
    static func maxPixelSize(for pointSize: CGSize, multiplier: CGFloat) -> CGFloat? {
        guard pointSize.width.isFinite, pointSize.height.isFinite, pointSize.width > 0,
            pointSize.height > 0, multiplier.isFinite, multiplier > 0
        else { return nil }

        return Swift.max(pointSize.width, pointSize.height) * multiplier
    }
}

struct DownsampleImageProcessor: ImageProcessor {
    let pointSize: CGSize
    let aggressiveness: Double

    func process(image: CIImage) async throws -> CIImage {
        guard
            let maxPixelSize = Self.maxPixelSize(
                for: pointSize, multiplier: Self.multiplier(for: aggressiveness))
        else {
            Logger.reader.debug("Skipping image downsampling: invalid display size \(pointSize)")
            return image
        }
        let sourceMaxPixelSize = Swift.max(image.extent.width, image.extent.height)
        guard sourceMaxPixelSize.isFinite, sourceMaxPixelSize > maxPixelSize else {
            Logger.reader.debug(
                "Skipping image downsampling: source max dimension \(sourceMaxPixelSize) px does not exceed target \(maxPixelSize) px"
            )
            return image
        }

        let scale = maxPixelSize / sourceMaxPixelSize
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    private static func multiplier(for aggressiveness: Double) -> CGFloat {
        guard aggressiveness.isFinite else { return 2 }

        let normalizedAggressiveness = min(max(aggressiveness, 0), 1)
        return 3 - (CGFloat(normalizedAggressiveness) * 2)
    }
}

struct UpscalingImageProcessor: ImageProcessor {
    let context: Int
    let pointSize: CGSize
    let threshold: Double

    func process(image: CIImage) async throws -> CIImage {
        guard threshold.isFinite else {
            Logger.upscaling.debug("Skipping image upscaling: invalid threshold \(threshold)")
            return image
        }
        guard threshold > 0 else {
            Logger.upscaling.debug("Skipping image upscaling: sensitivity is off")
            return image
        }
        guard let maxPixelSize = Self.maxPixelSize(for: pointSize, multiplier: CGFloat(threshold))
        else {
            Logger.upscaling.debug("Skipping image upscaling: invalid display size \(pointSize)")
            return image
        }

        let sourceMaxPixelSize = Swift.max(image.extent.width, image.extent.height)
        guard sourceMaxPixelSize.isFinite, sourceMaxPixelSize > 0 else {
            Logger.upscaling.debug(
                "Skipping image upscaling: invalid source max dimension \(sourceMaxPixelSize) px")
            return image
        }
        guard sourceMaxPixelSize < maxPixelSize else {
            Logger.upscaling.debug(
                "Skipping image upscaling: source max dimension \(sourceMaxPixelSize) px meets or exceeds threshold \(maxPixelSize) px"
            )
            return image
        }

        return try await Upscaling.shared.upscale(image, context: context)
    }
}
