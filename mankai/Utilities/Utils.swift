//
//  Utils.swift
//  mankai
//
//  Created by Travis XU on 27/6/2025.
//

import CoreGraphics
import ImageIO
import SwiftUI
import UIKit

extension UIApplication {
    static var windowBounds: CGRect {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.bounds ?? UIScreen.main.bounds
    }
}

func statusText(_ status: Status?) -> String {
    guard let status = status else { return String(localized: "nil") }
    switch status {
    case .any:
        return String(localized: "any")
    case .onGoing:
        return String(localized: "onGoing")
    case .ended:
        return String(localized: "ended")
    }
}

extension UIDevice {
    static var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    static var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
}

extension View {
    func apply<V: View>(@ViewBuilder _ block: (Self) -> V) -> V {
        block(self)
    }
}

enum ImageFormat: String {
    case unknown
    case png
    case jpeg = "jpg"
    case gif
    case tiff
    case webp

    var mimeType: String {
        switch self {
        case .png: return "image/png"
        case .jpeg: return "image/jpeg"
        case .gif: return "image/gif"
        case .tiff: return "image/tiff"
        case .webp: return "image/webp"
        case .unknown: return "application/octet-stream"
        }
    }
}

extension Data {
    var imageFormat: ImageFormat {
        guard count >= 4 else { return .unknown }

        var header = [UInt8](repeating: 0, count: 4)
        copyBytes(to: &header, count: 4)

        switch header {
        case let h where h[0] == 0x89 && h[1] == 0x50 && h[2] == 0x4E && h[3] == 0x47:
            return .png
        case let h where h[0] == 0xFF && h[1] == 0xD8:
            return .jpeg
        case let h where h[0] == 0x47 && h[1] == 0x49 && h[2] == 0x46:
            return .gif
        case let h where h[0] == 0x49 || h[0] == 0x4D:
            return .tiff
        case let h where h[0] == 0x52 && h[1] == 0x49 && h[2] == 0x46 && h[3] == 0x46:
            return .webp
        default:
            return .unknown
        }
    }

    func detectImageMimeType() -> String {
        imageFormat.mimeType
    }
}

extension NSData {
    var imageFormat: ImageFormat {
        (self as Data).imageFormat
    }
}

extension Data {
    func downsampledImage(
        to pointSize: CGSize,
        scale: CGFloat = UIScreen.main.scale
    ) -> UIImage? {
        guard pointSize.width.isFinite,
            pointSize.height.isFinite,
            pointSize.width > 0,
            pointSize.height > 0,
            scale.isFinite,
            scale > 0
        else {
            return nil
        }

        let maxPixelSize = Swift.max(pointSize.width, pointSize.height) * scale
        let sourceOptions =
            [
                kCGImageSourceShouldCache: false
            ] as CFDictionary

        guard let source = CGImageSourceCreateWithData(self as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}

func Copy<T: Codable>(of object: T) -> T? {
    do {
        let json = try JSONEncoder().encode(object)
        return try JSONDecoder().decode(T.self, from: json)
    } catch {
        Logger.general.error("Failed to copy object", error: error)
        return nil
    }
}
