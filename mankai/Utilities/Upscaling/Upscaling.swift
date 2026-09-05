//
//  Upscaling.swift
//  mankai
//
//  Created by Travis XU on 3/9/2026.
//

import CoreGraphics
import CoreImage
import CoreML
import CoreVideo
import Foundation

/// Runs `UpscalingModel` on images of any pixel dimensions by splitting them into tiles.
///
/// `context` pixels are included around every tile's useful area so the model can infer across tile boundaries.
/// Neighboring outputs are feathered across their shared context when the tiles are stitched together.
actor Upscaling {
    static let shared = Upscaling()

    static let inputTileSize = 256
    static let scaleFactor = 2
    private static let tileBatchSize = 4

    /// How long to keep the model loaded after the last upscale.
    private static let unloadDelay: Duration = .seconds(600)

    // MARK: - Properties

    private struct Runtime {
        let model: UpscalingModel
        let ciContext: CIContext
    }

    private struct Tile {
        let input: UpscalingModelInput
        let contentX: Int
        let contentY: Int
        let contentWidth: Int
        let contentHeight: Int
        let inputX: Int
        let inputY: Int
    }

    private var runtime: Runtime?
    private var pendingUnloadTask: Task<Void, Never>?

    private init() {}

    // MARK: - Manual Unloading

    func unloadImmediately() {
        cancelScheduledUnload()
        unloadRuntime()
    }

    /// Returns a 2x upscaled image whose origin is zero and whose pixel dimensions are exactly twice those of `image`.
    ///
    /// Valid context values are `0...127`. A context of `0` processes independent
    /// 256-pixel tiles; larger values reduce seams at the cost of processing more tiles.
    func upscale(_ image: CIImage, context: Int) throws -> CIImage {
        try Task.checkCancellation()
        let clock = ContinuousClock()
        let startedAt = clock.now
        cancelScheduledUnload()
        defer { scheduleUnloadIfNeeded() }

        try Self.validate(context: context)
        let runtime = try loadRuntimeIfNeeded()
        let sourceBounds = try Self.pixelBounds(for: image)
        let sourceWidth = Int(sourceBounds.width)
        let sourceHeight = Int(sourceBounds.height)
        let contentSize = Self.inputTileSize - (2 * context)
        let horizontalTileCount = (sourceWidth + contentSize - 1) / contentSize
        let verticalTileCount = (sourceHeight + contentSize - 1) / contentSize
        let blendWidth = context * Self.scaleFactor
        let outputBounds = CGRect(
            x: 0, y: 0, width: CGFloat(sourceWidth * Self.scaleFactor),
            height: CGFloat(sourceHeight * Self.scaleFactor))

        Logger.upscaling.debug(
            "Upscaling \(sourceWidth)x\(sourceHeight) image using \(horizontalTileCount)x\(verticalTileCount) tiles with \(context)-pixel context"
        )

        let source = image.clampedToExtent().cropped(to: sourceBounds)
            .transformed(
                by: CGAffineTransform(
                    translationX: -sourceBounds.origin.x, y: -sourceBounds.origin.y))
        let paddedSource = source.clampedToExtent()

        var stitchedImage: CIImage?
        var tileBatch: [Tile] = []
        tileBatch.reserveCapacity(Self.tileBatchSize)

        for y in Swift.stride(from: 0, to: sourceHeight, by: contentSize) {
            let contentHeight = min(contentSize, sourceHeight - y)
            let inputY = Self.inputOrigin(for: y, sourceLength: sourceHeight, context: context)

            for x in Swift.stride(from: 0, to: sourceWidth, by: contentSize) {
                try Task.checkCancellation()

                let contentWidth = min(contentSize, sourceWidth - x)
                let inputX = Self.inputOrigin(for: x, sourceLength: sourceWidth, context: context)
                let tile = makeInputTile(from: paddedSource, inputX: inputX, inputY: inputY)
                let inputBuffer = try makePixelBuffer(
                    width: Self.inputTileSize, height: Self.inputTileSize)

                Logger.upscaling.trace(
                    "Preparing tile at (\(inputX), \(inputY)) for content at (\(x), \(y)) with \(contentWidth)x\(contentHeight) useful pixels"
                )

                runtime.ciContext.render(
                    tile, to: inputBuffer,
                    bounds: CGRect(
                        x: 0, y: 0, width: CGFloat(Self.inputTileSize),
                        height: CGFloat(Self.inputTileSize)),
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB))

                tileBatch.append(
                    Tile(
                        input: UpscalingModelInput(input_image: inputBuffer), contentX: x,
                        contentY: y, contentWidth: contentWidth, contentHeight: contentHeight,
                        inputX: inputX, inputY: inputY))

                if tileBatch.count == Self.tileBatchSize {
                    stitchedImage = try process(
                        tileBatch, with: runtime, over: stitchedImage, blendWidth: blendWidth,
                        outputBounds: outputBounds)
                    tileBatch.removeAll(keepingCapacity: true)
                }
            }
        }

        if !tileBatch.isEmpty {
            stitchedImage = try process(
                tileBatch, with: runtime, over: stitchedImage, blendWidth: blendWidth,
                outputBounds: outputBounds)
        }

        guard let stitchedImage else {
            Logger.upscaling.error("Upscaling produced no output tiles")
            throw MankaiErrorCode.readerUpscalingInvalidInputImage.makeError()
        }

        let elapsed = startedAt.duration(to: clock.now).components
        let elapsedMilliseconds =
            (Double(elapsed.seconds) * 1_000)
            + (Double(elapsed.attoseconds) / 1_000_000_000_000_000)
        Logger.upscaling.debug(
            "Upscaling completed with \(Int(outputBounds.width))x\(Int(outputBounds.height)) output in \(String(format: "%.2f", elapsedMilliseconds)) ms"
        )
        return stitchedImage.cropped(to: outputBounds)
    }

    private func process(
        _ tiles: [Tile], with runtime: Runtime, over stitchedImage: CIImage?, blendWidth: Int,
        outputBounds: CGRect
    ) throws -> CIImage? {
        try Task.checkCancellation()
        Logger.upscaling.trace("Predicting a batch of \(tiles.count) tiles")

        let predictions = try runtime.model.predictions(inputs: tiles.map(\.input))
        try Task.checkCancellation()

        guard predictions.count == tiles.count else {
            Logger.upscaling.error(
                "Upscaling model returned \(predictions.count) predictions for \(tiles.count) input tiles"
            )
            throw MankaiErrorCode.readerUpscalingInvalidInputImage.makeError(
                messageOverride:
                    "The upscaling model returned an unexpected number of tile predictions.")
        }

        var result = stitchedImage
        for (tile, prediction) in zip(tiles, predictions) {
            try Task.checkCancellation()
            let outputTile = extendedOutput(
                from: prediction.output_image, contentX: tile.contentX, contentY: tile.contentY,
                contentWidth: tile.contentWidth, contentHeight: tile.contentHeight,
                inputX: tile.inputX, inputY: tile.inputY, blendWidth: blendWidth,
                outputBounds: outputBounds)

            result = stitch(
                outputTile, over: result, contentX: tile.contentX, contentY: tile.contentY,
                blendWidth: blendWidth)
        }

        return result
    }

    private func makeInputTile(from image: CIImage, inputX: Int, inputY: Int) -> CIImage {
        let tileBounds = CGRect(
            x: CGFloat(inputX), y: CGFloat(inputY), width: CGFloat(Self.inputTileSize),
            height: CGFloat(Self.inputTileSize))

        return image.cropped(to: tileBounds)
            .transformed(
                by: CGAffineTransform(translationX: -tileBounds.origin.x, y: -tileBounds.origin.y)
            )
            .cropped(
                to: CGRect(
                    x: 0, y: 0, width: CGFloat(Self.inputTileSize),
                    height: CGFloat(Self.inputTileSize)))
    }

    private func extendedOutput(
        from pixelBuffer: CVPixelBuffer, contentX: Int, contentY: Int, contentWidth: Int,
        contentHeight: Int, inputX: Int, inputY: Int, blendWidth: Int, outputBounds: CGRect
    ) -> CIImage {
        let scale = Self.scaleFactor
        let contentBounds = CGRect(
            x: CGFloat(contentX * scale), y: CGFloat(contentY * scale),
            width: CGFloat(contentWidth * Self.scaleFactor),
            height: CGFloat(contentHeight * Self.scaleFactor))
        let modelBounds = CGRect(
            x: CGFloat(inputX * scale), y: CGFloat(inputY * scale),
            width: CGFloat(Self.inputTileSize * scale), height: CGFloat(Self.inputTileSize * scale))
        let extendedBounds =
            contentBounds.insetBy(dx: -CGFloat(blendWidth), dy: -CGFloat(blendWidth))
            .intersection(modelBounds).intersection(outputBounds)
        let localBounds = extendedBounds.offsetBy(
            dx: -CGFloat(inputX * scale), dy: -CGFloat(inputY * scale))

        return CIImage(cvPixelBuffer: pixelBuffer).cropped(to: localBounds)
            .transformed(
                by: CGAffineTransform(
                    translationX: CGFloat(inputX * scale), y: CGFloat(inputY * scale)))
    }

    private func stitch(
        _ outputTile: CIImage, over stitchedImage: CIImage?, contentX: Int, contentY: Int,
        blendWidth: Int
    ) -> CIImage {
        guard let stitchedImage else { return outputTile }
        guard blendWidth > 0 else { return outputTile.composited(over: stitchedImage) }

        let bounds = outputTile.extent
        let width = CGFloat(blendWidth)
        let contentMinX = CGFloat(contentX * Self.scaleFactor)
        let contentMinY = CGFloat(contentY * Self.scaleFactor)
        var mask: CIImage?

        if bounds.minX < contentMinX {
            mask = smoothGradient(
                from: CGPoint(x: bounds.minX, y: bounds.midY),
                to: CGPoint(x: min(bounds.maxX, contentMinX + width), y: bounds.midY),
                bounds: bounds)
        }

        if bounds.minY < contentMinY,
            let bottomMask = smoothGradient(
                from: CGPoint(x: bounds.midX, y: bounds.minY),
                to: CGPoint(x: bounds.midX, y: min(bounds.maxY, contentMinY + width)),
                bounds: bounds)
        {
            mask =
                mask.map {
                    $0.applyingFilter(
                        "CIMultiplyCompositing",
                        parameters: [kCIInputBackgroundImageKey: bottomMask]
                    )
                    .cropped(to: bounds)
                } ?? bottomMask
        }

        guard let mask else { return outputTile.composited(over: stitchedImage) }

        return
            outputTile.applyingFilter(
                "CIBlendWithMask",
                parameters: [kCIInputBackgroundImageKey: stitchedImage, kCIInputMaskImageKey: mask]
            )
            .cropped(to: stitchedImage.extent.union(outputTile.extent))
    }

    private func smoothGradient(from start: CGPoint, to end: CGPoint, bounds: CGRect) -> CIImage? {
        guard
            let filter = CIFilter(
                name: "CISmoothLinearGradient",
                parameters: [
                    "inputPoint0": CIVector(cgPoint: start), "inputPoint1": CIVector(cgPoint: end),
                    "inputColor0": CIColor(red: 0, green: 0, blue: 0),
                    "inputColor1": CIColor(red: 1, green: 1, blue: 1)
                ])
        else { return nil }

        return filter.outputImage?.cropped(to: bounds)
    }

    /// Keeps trailing partial tiles close to the image edge instead of filling most of the model input with repeated edge pixels.
    /// The useful content's position within the input tile may therefore differ from `context` and must be accounted for when cropping output.
    private static func inputOrigin(for contentOrigin: Int, sourceLength: Int, context: Int) -> Int
    {
        let preferredOrigin = contentOrigin - context
        let trailingOrigin = sourceLength + context - inputTileSize
        return max(-context, min(preferredOrigin, trailingOrigin))
    }

    // MARK: - Runtime Management

    private func loadRuntimeIfNeeded() throws -> Runtime {
        if let runtime { return runtime }

        let configuration = MLModelConfiguration()
        if #available(iOS 18.0, *) {
            var optimizationHints = MLOptimizationHints()
            optimizationHints.specializationStrategy = .fastPrediction
            configuration.optimizationHints = optimizationHints
        }

        let loadedRuntime = Runtime(
            model: try UpscalingModel(configuration: configuration), ciContext: CIContext())
        runtime = loadedRuntime
        Logger.upscaling.debug("Upscaling model loaded")
        return loadedRuntime
    }

    private func scheduleUnloadIfNeeded() {
        guard runtime != nil else { return }

        cancelScheduledUnload()

        Logger.upscaling.debug(
            "Scheduling upscaling model unload after 60 seconds without upscales")

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
        Logger.upscaling.debug("Cancelled scheduled upscaling model unload")
    }

    private func unloadRuntime() {
        guard runtime != nil else { return }

        runtime = nil
        Logger.upscaling.debug("Upscaling model unloaded")
    }

    private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            attributes as CFDictionary, &pixelBuffer)

        guard status == kCVReturnSuccess, let pixelBuffer else {
            Logger.upscaling.error(
                "Failed to create upscaling pixel buffer; Core Video status: \(status)")
            throw MankaiErrorCode.readerUpscalingFailedToCreatePixelBuffer.makeError()
        }

        return pixelBuffer
    }

    private static func validate(context: Int) throws {
        guard context >= 0, context < inputTileSize / 2 else {
            Logger.upscaling.error("Invalid tile context: \(context); expected 0...127")
            throw MankaiErrorCode.readerUpscalingInvalidTileContext.makeError()
        }
    }

    private static func pixelBounds(for image: CIImage) throws -> CGRect {
        let extent = image.extent.standardized
        guard extent.origin.x.isFinite, extent.origin.y.isFinite, extent.width.isFinite,
            extent.height.isFinite, extent.width > 0, extent.height > 0
        else {
            Logger.upscaling.error(
                "Invalid input image extent: \(String(describing: image.extent))")
            throw MankaiErrorCode.readerUpscalingInvalidInputImage.makeError()
        }

        let bounds = extent.integral
        guard bounds.width <= CGFloat(Int.max / scaleFactor),
            bounds.height <= CGFloat(Int.max / scaleFactor)
        else {
            Logger.upscaling.error(
                "Input image is too large to upscale: \(bounds.width)x\(bounds.height)")
            throw MankaiErrorCode.readerUpscalingInvalidInputImage.makeError()
        }

        return bounds
    }
}
