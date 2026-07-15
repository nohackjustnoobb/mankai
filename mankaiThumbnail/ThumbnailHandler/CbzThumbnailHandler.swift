//
//  CbzThumbnailHandler.swift
//  mankaiThumbnail
//
//  Created by Travis XU on 16/7/2026.
//

import UIKit
import ZIPFoundation

/// Extracts the cover image (first page) of a CBZ comic archive.
final class CbzThumbnailHandler: ThumbnailHandler {
    let supportedExtensions: Set<String> = ["cbz"]

    /// Image extensions supported as cover candidates inside a CBZ archive.
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "webp", "tiff", "tif",
    ]

    func coverImage(from url: URL) throws -> UIImage? {
        let archive = try Archive(url: url, accessMode: .read)

        // Pick the first image entry, sorted by path so the cover is a stable
        // "first page" regardless of zip ordering.
        let firstImage = archive
            .compactMap { entry -> Entry? in
                guard entry.type == .file, Self.isImageEntry(entry) else { return nil }
                return entry
            }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .first

        guard let entry = firstImage else { return nil }

        var data = Data()
        _ = try archive.extract(entry, consumer: { chunk in
            data.append(chunk)
        })

        return UIImage(data: data)
    }

    // MARK: - Helpers

    private static func isImageEntry(_ entry: Entry) -> Bool {
        let name = (entry.path as NSString).lastPathComponent

        // Ignore hidden files and macOS metadata folders.
        if name.hasPrefix(".") || entry.path.contains("__MACOSX/") { return false }

        let ext = (name as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }
}
