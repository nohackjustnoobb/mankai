//
//  CbzThumbnailHandler.swift
//  mankaiThumbnail
//
//  Created by Travis XU on 16/7/2026.
//

import UIKit
import ZIPFoundation

/// Extracts the cover image of a CBZ comic archive.
final class CbzThumbnailHandler: ThumbnailHandler {
    let supportedExtensions: Set<String> = ["cbz"]

    /// Image extensions supported as cover candidates inside a CBZ archive.
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "webp", "tiff", "tif",
    ]

    func coverImage(from url: URL) throws -> UIImage? {
        let archive = try Archive(url: url, accessMode: .read)

        let imageEntries = archive
            .compactMap { entry -> Entry? in
                guard entry.type == .file, Self.isImageEntry(entry) else { return nil }
                return entry
            }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        guard let firstImage = imageEntries.first else { return nil }

        let entry = Self.comicInfoEntry(in: archive).flatMap { infoEntry in
            try? Self.entryData(archive: archive, entry: infoEntry)
        }.flatMap { data in
            ComicInfoCoverParser.frontCoverIndex(from: data)
        }.flatMap { index in
            imageEntries.indices.contains(index) ? imageEntries[index] : nil
        } ?? firstImage

        return try UIImage(data: Self.entryData(archive: archive, entry: entry))
    }

    // MARK: - Helpers

    private static func entryData(archive: Archive, entry: Entry) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry, consumer: { chunk in
            data.append(chunk)
        })
        return data
    }

    private static func comicInfoEntry(in archive: Archive) -> Entry? {
        archive["ComicInfo.xml"] ?? archive.first { entry in
            guard entry.type == .file else { return false }
            let normalizedPath = entry.path.replacingOccurrences(of: "\\", with: "/")
            let name = (normalizedPath as NSString).lastPathComponent
            return !normalizedPath.contains("__MACOSX/")
                && name.caseInsensitiveCompare("ComicInfo.xml") == .orderedSame
        }
    }

    private static func isImageEntry(_ entry: Entry) -> Bool {
        let name = (entry.path as NSString).lastPathComponent

        // Ignore hidden files and macOS metadata folders.
        if name.hasPrefix(".") || entry.path.contains("__MACOSX/") { return false }

        let ext = (name as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }
}
