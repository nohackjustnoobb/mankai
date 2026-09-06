//
//  SmartGrouping.swift
//  mankai
//
//  Created by Travis XU on 12/2/2026.
//

import CoreGraphics
import CoreImage
import CoreML
import Foundation

// MARK: - SmartGrouping

actor SmartGrouping {
    /// The shared singleton instance.
    static let shared = SmartGrouping()

    /// The expected input size for the model (width × height).
    static let inputSize = CGSize(width: 224, height: 224)

    /// How long to keep the model loaded after the last prediction.
    private static let unloadDelay: Duration = .seconds(60)

    // MARK: - Properties

    private struct Runtime {
        let model: SmartGroupingModel
        let ciContext: CIContext
    }

    private var runtime: Runtime?
    private var pendingUnloadTask: Task<Void, Never>?

    // MARK: - Manual Unloading

    func unloadImmediately() {
        cancelScheduledUnload()
        unloadRuntime()
    }

    // MARK: - Prediction

    /// Run adjacency prediction on two preprocessed image slides.
    ///
    /// - Parameters:
    ///   - leftSlide: The right edge of the page on the left.
    ///   - rightSlide: The left edge of the page on the right.
    /// - Returns: A `Double` in [0, 1]. Higher values indicate the patches are likely adjacent.
    /// - Throws: If preprocessing or inference fails.
    func predict(leftSlide: CIImage, rightSlide: CIImage) throws -> Double {
        try Task.checkCancellation()
        cancelScheduledUnload()
        defer { scheduleUnloadIfNeeded() }

        let runtime = try loadRuntimeIfNeeded()

        let targetW = Int(Self.inputSize.width)
        let targetH = Int(Self.inputSize.height)

        let inputImage = mergeSlides(left: leftSlide, right: rightSlide)

        let buffer = try createPixelBuffer(
            from: inputImage, width: targetW, height: targetH, ciContext: runtime.ciContext)

        let input = SmartGroupingModelInput(image: buffer)

        try Task.checkCancellation()
        Logger.smartGrouping.debug("Predicting adjacency for image pair")
        let output = try runtime.model.prediction(input: input)
        try Task.checkCancellation()

        let score = output.adjacency_score[0].doubleValue
        Logger.smartGrouping.debug("Prediction result: \(score)")
        return score
    }

    private func mergeSlides(left: CIImage, right: CIImage) -> CIImage {
        let slideWidth = Self.inputSize.width / 2
        return right.transformed(by: CGAffineTransform(translationX: slideWidth, y: 0))
            .composited(over: left).cropped(to: CGRect(origin: .zero, size: Self.inputSize))
    }

    // MARK: - Pixel Buffer

    private func createPixelBuffer(
        from image: CIImage, width: Int, height: Int, ciContext: CIContext
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            attributes as CFDictionary, &pixelBuffer)

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw MankaiErrorCode.readerAdjacencyFailedToCreatePixelBuffer.makeError()
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        ciContext.render(image, to: buffer)

        return buffer
    }

    // MARK: - Runtime Management

    private func loadRuntimeIfNeeded() throws -> Runtime {
        if let runtime { return runtime }

        let loadedRuntime = Runtime(
            model: try SmartGroupingModel(configuration: .init()),
            ciContext: CIContext(options: [.cacheIntermediates: false]))
        runtime = loadedRuntime
        Logger.smartGrouping.debug("Smart grouping model loaded")
        return loadedRuntime
    }

    private func scheduleUnloadIfNeeded() {
        guard runtime != nil else { return }

        cancelScheduledUnload()

        Logger.smartGrouping.debug(
            "Scheduling smart grouping model unload after 60 seconds without predictions")

        pendingUnloadTask = Task { [weak self] in
            do { try await Task.sleep(for: Self.unloadDelay) } catch { return }

            await self?.performScheduledUnload()
        }
    }

    private func performScheduledUnload() {
        guard !Task.isCancelled else { return }

        pendingUnloadTask = nil
        unloadRuntime()
    }

    private func cancelScheduledUnload() {
        guard pendingUnloadTask != nil else { return }

        pendingUnloadTask?.cancel()
        pendingUnloadTask = nil
        Logger.smartGrouping.debug("Cancelled scheduled smart grouping model unload")
    }

    private func unloadRuntime() {
        guard runtime != nil else { return }

        runtime = nil
        Logger.smartGrouping.debug("Smart grouping model unloaded")
    }
}
