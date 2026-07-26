//
//  AdjacencyModelWrapper.swift
//  mankai
//
//  Created by Travis XU on 12/2/2026.
//

import CoreGraphics
import CoreImage
import CoreML
import Foundation
import UIKit

// MARK: - AdjacencyModelWrapper

class AdjacencyModelWrapper {
    /// The shared singleton instance.
    static let shared = try? AdjacencyModelWrapper()

    /// The expected input size for the model (width × height).
    private static let inputSize = CGSize(width: 224, height: 224)

    // MARK: - Properties

    private let model: AdjacencyModel
    private let ciContext = CIContext()

    // MARK: - Initialization

    private init() throws {
        Logger.adjacencyModel.debug("Initializing AdjacencyModelWrapper")
        model = try AdjacencyModel()
    }

    // MARK: - Prediction

    /// Run adjacency prediction on two image patches.
    ///
    /// - Parameters:
    ///   - image1: The left patch as a `UIImage`.
    ///   - image2: The right patch as a `UIImage`.
    /// - Returns: A `Double` in [0, 1]. Higher values indicate the patches are likely adjacent.
    /// - Throws: If preprocessing or inference fails.
    func predict(image1: UIImage, image2: UIImage) throws -> Double {
        let targetW = Int(Self.inputSize.width)
        let targetH = Int(Self.inputSize.height)

        guard let ci1 = image1.ciImage ?? image1.cgImage.map({ CIImage(cgImage: $0) }),
              let ci2 = image2.ciImage ?? image2.cgImage.map({ CIImage(cgImage: $0) })
        else {
            throw MankaiErrorCode.readerAdjacencyInvalidInputImage.makeError()
        }

        // Merge the right edge of image1 and left edge of image2 side-by-side,
        // then resize the combined image to 224×224.
        let merged = mergePatches(left: ci1, right: ci2)
        let resized = resizeToTarget(merged, targetWidth: targetW, targetHeight: targetH)

        // Convert to CVPixelBuffer
        let buffer = try createPixelBuffer(from: resized, width: targetW, height: targetH)

        // Build input
        let input = AdjacencyModelInput(image: buffer)

        // Run inference
        Logger.adjacencyModel.debug("Predicting adjacency for image pair")
        let output = try model.prediction(input: input)

        let score = output.adjacency_score[0].doubleValue
        Logger.adjacencyModel.debug("Prediction result: \(score)")
        return score
    }

    // MARK: - Preprocessing

    /// Merge the rightmost 224 px of `left` and the leftmost 224 px of `right`
    /// side-by-side into a single 448-wide `CIImage` whose origin is at (0, 0).
    private func mergePatches(left: CIImage, right: CIImage) -> CIImage {
        let stripWidth = CGFloat(Int(Self.inputSize.width)) // 224

        // Normalise both images to origin (0, 0)
        let normLeft = left.transformed(
            by: CGAffineTransform(translationX: -left.extent.origin.x, y: -left.extent.origin.y)
        )
        let normRight = right.transformed(
            by: CGAffineTransform(translationX: -right.extent.origin.x, y: -right.extent.origin.y)
        )

        let height = max(normLeft.extent.height, normRight.extent.height)

        // Crop: rightmost 224 px of the left image, translated so its origin is at x=0
        let cropLeftX = max(0, normLeft.extent.width - stripWidth)
        let leftStrip = normLeft.cropped(
            to: CGRect(x: cropLeftX, y: 0, width: min(stripWidth, normLeft.extent.width), height: normLeft.extent.height)
        ).transformed(by: CGAffineTransform(translationX: -cropLeftX, y: 0))

        // Crop: leftmost 224 px of the right image, placed immediately to the right of leftStrip
        let rightStrip = normRight.cropped(
            to: CGRect(x: 0, y: 0, width: min(stripWidth, normRight.extent.width), height: normRight.extent.height)
        ).transformed(by: CGAffineTransform(translationX: stripWidth, y: 0))

        // Composite rightStrip over leftStrip
        let merged = rightStrip.composited(over: leftStrip)

        // Translate so the merged image origin is exactly (0, 0)
        return merged.transformed(
            by: CGAffineTransform(translationX: -merged.extent.origin.x, y: -merged.extent.origin.y)
        ).cropped(to: CGRect(x: 0, y: 0, width: stripWidth * 2, height: height))
    }

    private func resizeToTarget(
        _ ciImage: CIImage, targetWidth: Int, targetHeight: Int
    ) -> CIImage {
        let scaleX = CGFloat(targetWidth) / ciImage.extent.width
        let scaleY = CGFloat(targetHeight) / ciImage.extent.height

        return ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    }

    // MARK: - Pixel Buffer

    private func createPixelBuffer(from image: CIImage, width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw MankaiErrorCode.readerAdjacencyFailedToCreatePixelBuffer.makeError()
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        ciContext.render(image, to: buffer)

        return buffer
    }
}
