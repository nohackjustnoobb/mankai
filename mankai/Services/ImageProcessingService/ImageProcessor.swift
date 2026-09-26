//
//  ImageProcessor.swift
//  mankai
//
//  Created by Travis XU on 3/9/2026.
//

import CoreImage
import Foundation

protocol ImageProcessor: Sendable {
    static var type: String { get }
    static var titleKey: LocalizedStringResource { get }
    static var descriptionKey: LocalizedStringResource { get }
    static var defaultProcessor: any ImageProcessor { get }
    /// Fast processors can finish before the reader needs a temporary image.
    var isFast: Bool { get }

    /// Applies this processor's operation to the current pipeline image.
    func process(image: CIImage, pointSize: CGSize) async throws -> CIImage

    /// Encodes this processor's settings and its service-owned execution metadata.
    func encode(id: String, order: Int, isEnabled: Bool) throws -> ImageProcessorModel
    static func decode(_ model: ImageProcessorModel) throws -> any ImageProcessor
}

extension ImageProcessor {
    static func maxPixelSize(for pointSize: CGSize, multiplier: CGFloat) -> CGFloat? {
        guard pointSize.width.isFinite, pointSize.height.isFinite, pointSize.width > 0,
            pointSize.height > 0, multiplier.isFinite, multiplier > 0
        else { return nil }

        return Swift.max(pointSize.width, pointSize.height) * multiplier
    }
}
