//
//  DownsampleImageProcessor.swift
//  mankai
//
//  Created by Travis XU on 26/9/2026.
//

import CoreImage
import Foundation

struct DownsampleImageProcessor: ImageProcessor {
    static let type = "downsample"
    static let titleKey: LocalizedStringResource = "downsampleImages"
    static let descriptionKey: LocalizedStringResource = "downsampleImagesDescription"
    static var defaultProcessor: any ImageProcessor { Self(aggressiveness: 0.5) }
    let isFast = true
    let aggressiveness: Double

    var memorySavingsLabel: LocalizedStringResource {
        switch aggressiveness { case ..<0.25: return "downsampleMemorySavingsLow" case ..<0.75:
            return "downsampleMemorySavingsBalanced"
            default: return "downsampleMemorySavingsHigh"
        }
    }

    func encode(id: String, order: Int, isEnabled: Bool) throws -> ImageProcessorModel {
        let configuration = try JSONEncoder().encode(Configuration(aggressiveness: aggressiveness))
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
        guard configuration.aggressiveness.isFinite, (0...1).contains(configuration.aggressiveness)
        else { throw MankaiErrorCode.imageProcessingInvalidConfiguration.makeError() }
        return Self(aggressiveness: configuration.aggressiveness)
    }

    private struct Configuration: Codable { let aggressiveness: Double }

    func process(image: CIImage, pointSize: CGSize) async throws -> CIImage {
        guard
            let maxPixelSize = Self.maxPixelSize(
                for: pointSize, multiplier: Self.multiplier(for: aggressiveness))
        else {
            Logger.imageProcessingService.debug(
                "Skipping image downsampling: invalid display size \(pointSize)")
            return image
        }
        let sourceMaxPixelSize = Swift.max(image.extent.width, image.extent.height)
        guard sourceMaxPixelSize.isFinite, sourceMaxPixelSize > maxPixelSize else {
            Logger.imageProcessingService.debug(
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
