//
//  CbrThumbnailHandler.swift
//  mankaiThumbnail
//
//  Created by Travis XU on 16/7/2026.
//

import UIKit
import UnrarKit

/// Extracts the cover image (first page) of a CBR comic archive.
final class CbrThumbnailHandler: ThumbnailHandler {
    let supportedExtensions: Set<String> = ["cbr"]

    /// Image extensions supported as cover candidates inside a CBR archive.
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "webp", "tiff", "tif",
    ]

    func coverImage(from url: URL) throws -> UIImage? {
        let archive = try URKArchive(url: url)

        // Pick the first image path using the same stable natural ordering as
        // the in-app parser and the CBZ thumbnail handler.
        let firstImage = try archive.listFilenames()
            .filter(Self.isImagePath)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .first

        guard let firstImage else { return nil }
        let data = try archive.extractData(fromFile: firstImage)
        return UIImage(data: data)
    }

    // MARK: - Helpers

    private static func isImagePath(_ path: String) -> Bool {
        let normalizedPath = path.replacingOccurrences(of: "\\", with: "/")
        let name = (normalizedPath as NSString).lastPathComponent

        // Ignore hidden files and macOS metadata folders.
        if name.hasPrefix(".") || normalizedPath.contains("__MACOSX/") { return false }

        let ext = (name as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }
}
