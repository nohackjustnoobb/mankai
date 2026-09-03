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
/// The corresponding part of the model output is discarded when the tiles are stitched together.
actor Upscaling {
    static let shared = Upscaling()

    static let inputTileSize = 256
    static let scaleFactor = 2

    /// How long to keep the model loaded after the last upscale.
    private static let unloadDelay: Duration = .seconds(60)

    // MARK: - Properties

    private struct Runtime {
        let model: UpscalingModel
        let ciContext: CIContext
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

        Logger.upscaling.debug(
            "Upscaling \(sourceWidth)x\(sourceHeight) image using \(horizontalTileCount)x\(verticalTileCount) tiles with \(context)-pixel context"
        )

        let source = image.clampedToExtent().cropped(to: sourceBounds)
            .transformed(
                by: CGAffineTransform(
                    translationX: -sourceBounds.origin.x, y: -sourceBounds.origin.y))
        let paddedSource = source.clampedToExtent()
        let inputBuffer = try makePixelBuffer(width: Self.inputTileSize, height: Self.inputTileSize)

        var stitchedImage: CIImage?

        for y in Swift.stride(from: 0, to: sourceHeight, by: contentSize) {
            let contentHeight = min(contentSize, sourceHeight - y)

            for x in Swift.stride(from: 0, to: sourceWidth, by: contentSize) {
                try Task.checkCancellation()

                let contentWidth = min(contentSize, sourceWidth - x)
                let tile = makeInputTile(
                    from: paddedSource, contentX: x, contentY: y, context: context)

                Logger.upscaling.trace(
                    "Predicting tile at (\(x), \(y)) with \(contentWidth)x\(contentHeight) useful pixels"
                )

                runtime.ciContext.render(
                    tile, to: inputBuffer,
                    bounds: CGRect(
                        x: 0, y: 0, width: CGFloat(Self.inputTileSize),
                        height: CGFloat(Self.inputTileSize)),
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB))

                let prediction = try runtime.model.prediction(input_image: inputBuffer)
                try Task.checkCancellation()
                let outputTile = usefulOutput(
                    from: prediction.output_image, contentX: x, contentY: y,
                    contentWidth: contentWidth, contentHeight: contentHeight, context: context)

                stitchedImage = stitchedImage.map { outputTile.composited(over: $0) } ?? outputTile
            }
        }

        guard let stitchedImage else {
            Logger.upscaling.error("Upscaling produced no output tiles")
            throw MankaiErrorCode.readerUpscalingInvalidInputImage.makeError()
        }

        let outputBounds = CGRect(
            x: 0, y: 0, width: CGFloat(sourceWidth * Self.scaleFactor),
            height: CGFloat(sourceHeight * Self.scaleFactor))
        Logger.upscaling.debug(
            "Upscaling completed with \(Int(outputBounds.width))x\(Int(outputBounds.height)) output"
        )
        return stitchedImage.cropped(to: outputBounds)
    }

    private func makeInputTile(from image: CIImage, contentX: Int, contentY: Int, context: Int)
        -> CIImage
    {
        let tileBounds = CGRect(
            x: CGFloat(contentX - context), y: CGFloat(contentY - context),
            width: CGFloat(Self.inputTileSize), height: CGFloat(Self.inputTileSize))

        return image.cropped(to: tileBounds)
            .transformed(
                by: CGAffineTransform(translationX: -tileBounds.origin.x, y: -tileBounds.origin.y)
            )
            .cropped(
                to: CGRect(
                    x: 0, y: 0, width: CGFloat(Self.inputTileSize),
                    height: CGFloat(Self.inputTileSize)))
    }

    private func usefulOutput(
        from pixelBuffer: CVPixelBuffer, contentX: Int, contentY: Int, contentWidth: Int,
        contentHeight: Int, context: Int
    ) -> CIImage {
        let scaledContext = context * Self.scaleFactor
        let usefulBounds = CGRect(
            x: CGFloat(scaledContext), y: CGFloat(scaledContext),
            width: CGFloat(contentWidth * Self.scaleFactor),
            height: CGFloat(contentHeight * Self.scaleFactor))

        return CIImage(cvPixelBuffer: pixelBuffer).cropped(to: usefulBounds)
            .transformed(
                by: CGAffineTransform(
                    translationX: CGFloat((contentX * Self.scaleFactor) - scaledContext),
                    y: CGFloat((contentY * Self.scaleFactor) - scaledContext)))
    }

    // MARK: - Runtime Management

    private func loadRuntimeIfNeeded() throws -> Runtime {
        if let runtime { return runtime }

        let loadedRuntime = Runtime(
            model: try UpscalingModel(configuration: .init()), ciContext: CIContext())
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
