//
//  UpscalingImageProcessor.swift
//  mankai
//
//  Created by Travis XU on 26/9/2026.
//

import CoreImage
import Foundation

struct UpscalingImageProcessor: ImageProcessor {
    static let type = "upscale"
    static let titleKey: LocalizedStringResource = "imageUpscaling"
    static let descriptionKey: LocalizedStringResource = "imageUpscalingDescription"
    static var defaultProcessor: any ImageProcessor { Self(context: 16, threshold: 1.5) }
    let isFast = false
    let context: Int
    let threshold: Double

    var sensitivityLabel: LocalizedStringResource {
        switch threshold { case ..<0.75: return "upscaleSensitivityVeryLow" case ..<1.25:
            return "upscaleSensitivityLow"
            case ..<1.75: return "upscaleSensitivityBalanced"
            case ..<2.25: return "upscaleSensitivityHigh"
            default: return "upscaleSensitivityMaximum"
        }
    }

    func encode(id: String, order: Int, isEnabled: Bool) throws -> ImageProcessorModel {
        let configuration = try JSONEncoder()
            .encode(Configuration(context: context, threshold: threshold))
        return ImageProcessorModel(
            id: id, type: Self.type, order: order, isEnabled: isEnabled,
            configuration: String(decoding: configuration, as: UTF8.self))
    }

    static func decode(_ model: ImageProcessorModel) throws -> any ImageProcessor {
        let configuration: Configuration
        do {
            configuration = try JSONDecoder()
                .decode(Configuration.self, from: Data(model.configuration.utf8))
        } catch {
            throw MankaiErrorCode.imageProcessingInvalidConfiguration.makeError(
                underlyingError: error)
        }
        guard (0...127).contains(configuration.context), configuration.threshold.isFinite,
            configuration.threshold > 0
        else { throw MankaiErrorCode.imageProcessingInvalidConfiguration.makeError() }
        return Self(context: configuration.context, threshold: configuration.threshold)
    }

    private struct Configuration: Codable {
        let context: Int
        let threshold: Double
    }

    func process(image: CIImage, pointSize: CGSize) async throws -> CIImage {
        guard threshold.isFinite else {
            Logger.imageProcessingService.debug(
                "Skipping image upscaling: invalid threshold \(threshold)")
            return image
        }
        guard threshold > 0 else {
            Logger.imageProcessingService.debug("Skipping image upscaling: sensitivity is off")
            return image
        }
        guard let maxPixelSize = Self.maxPixelSize(for: pointSize, multiplier: CGFloat(threshold))
        else {
            Logger.imageProcessingService.debug(
                "Skipping image upscaling: invalid display size \(pointSize)")
            return image
        }

        let sourceMaxPixelSize = Swift.max(image.extent.width, image.extent.height)
        guard sourceMaxPixelSize.isFinite, sourceMaxPixelSize > 0 else {
            Logger.imageProcessingService.debug(
                "Skipping image upscaling: invalid source max dimension \(sourceMaxPixelSize) px")
            return image
        }
        guard sourceMaxPixelSize < maxPixelSize else {
            Logger.imageProcessingService.debug(
                "Skipping image upscaling: source max dimension \(sourceMaxPixelSize) px meets or exceeds threshold \(maxPixelSize) px"
            )
            return image
        }

        return try await Upscaling.shared.upscale(image, context: context)
    }
}
