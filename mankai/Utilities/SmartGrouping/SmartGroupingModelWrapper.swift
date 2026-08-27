//
//  SmartGroupingModelWrapper.swift
//  mankai
//
//  Created by Travis XU on 24/8/2026.
//

import CoreGraphics
import CoreImage
import CoreML
import Foundation

struct ImageEdgeEmbeddings {
    let left: MLMultiArray
    let right: MLMultiArray
}

struct ClassifierPrediction {
    let rawLogit: Double
    let probability: Double
    let label: Int
}

enum SmartGroupingModelError: LocalizedError {
    case failedToCreatePixelBuffer

    var errorDescription: String? {
        switch self {
        case .failedToCreatePixelBuffer:
            return "Failed to create a pixel buffer for the smart grouping encoder."
        }
    }
}

// MARK: - EncoderWrapper

actor EncoderWrapper {
    static let shared = EncoderWrapper()

    private static let inputSize = CGSize(width: 224, height: 224)
    private static let minimumNormalizedWidth = inputSize.width
    private static let unloadDelay: Duration = .seconds(60)

    private struct Runtime {
        let model: SGEncoder
        let ciContext: CIContext
        let colorSpace: CGColorSpace
    }

    private var runtime: Runtime?
    private var pendingUnloadTask: Task<Void, Never>?

    func unloadImmediately() {
        cancelScheduledUnload()
        runtime = nil
    }

    /// Encodes the leftmost and rightmost 224-pixel strips of an image.
    ///
    /// The image is first resized to `SGConstants.NORMALIZED_HEIGHT` while
    /// preserving its aspect ratio. `nil` is returned when the normalized image
    /// is narrower than 224 pixels because it cannot provide a complete edge
    /// strip. The left and right strips may overlap.
    func predict(image: CIImage) throws -> ImageEdgeEmbeddings? {
        try Task.checkCancellation()

        guard let patches = makeEdgePatches(from: image) else {
            return nil
        }

        cancelScheduledUnload()
        defer { scheduleUnloadIfNeeded() }

        let runtime = try loadRuntimeIfNeeded()
        let width = Int(Self.inputSize.width)
        let height = Int(Self.inputSize.height)

        let leftBuffer = try makePixelBuffer(
            from: patches.left,
            width: width,
            height: height,
            runtime: runtime
        )
        let rightBuffer = try makePixelBuffer(
            from: patches.right,
            width: width,
            height: height,
            runtime: runtime
        )

        try Task.checkCancellation()
        let leftEmbedding = try runtime.model.prediction(image: leftBuffer).embedding
        try Task.checkCancellation()
        let rightEmbedding = try runtime.model.prediction(image: rightBuffer).embedding
        try Task.checkCancellation()

        return ImageEdgeEmbeddings(left: leftEmbedding, right: rightEmbedding)
    }

    private func makeEdgePatches(from image: CIImage) -> (left: CIImage, right: CIImage)? {
        let extent = image.extent.standardized
        guard
            extent.width.isFinite,
            extent.height.isFinite,
            extent.width > 0,
            extent.height > 0
        else {
            return nil
        }

        let imageAtOrigin =
            image
            .cropped(to: extent)
            .transformed(
                by: CGAffineTransform(
                    translationX: -extent.origin.x,
                    y: -extent.origin.y
                )
            )

        let normalizedHeight = CGFloat(SGConstants.NORMALIZED_HEIGHT)
        let scale = normalizedHeight / extent.height
        let normalizedWidth = extent.width * scale

        guard normalizedWidth >= Self.minimumNormalizedWidth else {
            return nil
        }

        let normalizedImage =
            imageAtOrigin
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .cropped(
                to: CGRect(
                    x: 0,
                    y: 0,
                    width: normalizedWidth,
                    height: normalizedHeight
                )
            )

        let stripWidth = Self.inputSize.width
        let leftStrip = normalizedImage.cropped(
            to: CGRect(x: 0, y: 0, width: stripWidth, height: normalizedHeight)
        )

        let rightOriginX = normalizedWidth - stripWidth
        let rightStrip =
            normalizedImage
            .cropped(
                to: CGRect(
                    x: rightOriginX,
                    y: 0,
                    width: stripWidth,
                    height: normalizedHeight
                )
            )
            .transformed(by: CGAffineTransform(translationX: -rightOriginX, y: 0))

        return (
            left: resizeToModelInput(leftStrip),
            right: resizeToModelInput(rightStrip)
        )
    }

    private func resizeToModelInput(_ image: CIImage) -> CIImage {
        let scaleX = Self.inputSize.width / image.extent.width
        let scaleY = Self.inputSize.height / image.extent.height

        return
            image
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: CGRect(origin: .zero, size: Self.inputSize))
    }

    private func makePixelBuffer(
        from image: CIImage,
        width: Int,
        height: Int,
        runtime: Runtime
    ) throws -> CVPixelBuffer {
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

        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw SmartGroupingModelError.failedToCreatePixelBuffer
        }

        runtime.ciContext.render(
            image,
            to: pixelBuffer,
            bounds: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
            colorSpace: runtime.colorSpace
        )

        return pixelBuffer
    }

    private func loadRuntimeIfNeeded() throws -> Runtime {
        if let runtime {
            return runtime
        }

        let loadedRuntime = Runtime(
            model: try SGEncoder(configuration: .init()),
            ciContext: CIContext(),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        runtime = loadedRuntime
        return loadedRuntime
    }

    private func scheduleUnloadIfNeeded() {
        guard runtime != nil else {
            return
        }

        cancelScheduledUnload()
        pendingUnloadTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.unloadDelay)
            } catch {
                return
            }

            await self?.performScheduledUnload()
        }
    }

    private func performScheduledUnload() {
        guard !Task.isCancelled else {
            return
        }

        pendingUnloadTask = nil
        runtime = nil
    }

    private func cancelScheduledUnload() {
        pendingUnloadTask?.cancel()
        pendingUnloadTask = nil
    }
}

// MARK: - ClassifierWrapper

actor ClassifierWrapper {
    static let shared = ClassifierWrapper()

    private static let trainingPrior = 0.5
    private static let unloadDelay: Duration = .seconds(60)

    private var model: SGClassifier?
    private var pendingUnloadTask: Task<Void, Never>?

    func unloadImmediately() {
        cancelScheduledUnload()
        model = nil
    }

    /// Classifies a pair of unit-length image embeddings.
    ///
    /// The model emits a training-distribution logit. This method applies the
    /// deployment-prior correction before calculating the probability and label.
    func predict(
        embedding1: MLMultiArray,
        embedding2: MLMultiArray
    ) throws -> ClassifierPrediction {
        try Task.checkCancellation()
        cancelScheduledUnload()
        defer { scheduleUnloadIfNeeded() }

        let model = try loadModelIfNeeded()
        let output = try model.prediction(
            embedding_1: embedding1,
            embedding_2: embedding2
        )
        try Task.checkCancellation()

        let rawLogit = output.logit[0].doubleValue
        let prior = configuredPrior() ?? SGConstants.DEFAULT_PRIOR
        let threshold = configuredThreshold() ?? SGConstants.DEFAULT_THRESHOLD
        let priorBias = logOdds(prior) - logOdds(Self.trainingPrior)
        let probability = sigmoid(rawLogit + priorBias)

        return ClassifierPrediction(
            rawLogit: rawLogit,
            probability: probability,
            label: probability >= threshold ? 1 : 0
        )
    }

    private func configuredPrior() -> Double? {
        guard
            let value =
                (UserDefaults.standard.object(
                    forKey: SettingsKey.smartGroupingPrior.rawValue
                ) as? NSNumber)?
                .doubleValue,
            value.isFinite,
            value > 0,
            value < 1
        else {
            return nil
        }

        return value
    }

    private func configuredThreshold() -> Double? {
        guard
            let value =
                (UserDefaults.standard.object(
                    forKey: SettingsKey.smartGroupingThreshold.rawValue
                ) as? NSNumber)?
                .doubleValue,
            value.isFinite,
            value >= 0,
            value <= 1
        else {
            return nil
        }

        return value
    }

    private func logOdds(_ probability: Double) -> Double {
        log(probability / (1 - probability))
    }

    private func sigmoid(_ value: Double) -> Double {
        if value >= 0 {
            return 1 / (1 + exp(-value))
        }

        let exponential = exp(value)
        return exponential / (1 + exponential)
    }

    private func loadModelIfNeeded() throws -> SGClassifier {
        if let model {
            return model
        }

        let loadedModel = try SGClassifier(configuration: .init())
        model = loadedModel
        return loadedModel
    }

    private func scheduleUnloadIfNeeded() {
        guard model != nil else {
            return
        }

        cancelScheduledUnload()
        pendingUnloadTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.unloadDelay)
            } catch {
                return
            }

            await self?.performScheduledUnload()
        }
    }

    private func performScheduledUnload() {
        guard !Task.isCancelled else {
            return
        }

        pendingUnloadTask = nil
        model = nil
    }

    private func cancelScheduledUnload() {
        pendingUnloadTask?.cancel()
        pendingUnloadTask = nil
    }
}
