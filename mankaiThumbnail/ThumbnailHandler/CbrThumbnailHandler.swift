//
//  CbrThumbnailHandler.swift
//  mankaiThumbnail
//
//  Created by Travis XU on 1/8/2026.
//

import UIKit
import UnrarKit

/// Extracts the cover image of a CBR comic archive.
final class CbrThumbnailHandler: ThumbnailHandler {
    let supportedExtensions: Set<String> = ["cbr"]

    /// Image extensions supported as cover candidates inside a CBR archive.
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "webp", "tiff", "tif",
    ]

    func coverImage(from url: URL) throws -> UIImage? {
        let archive = try URKArchive(url: url)
        let filenames = try archive.listFilenames()

        let imagePaths = filenames
            .filter(Self.isImagePath)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        guard let firstImage = imagePaths.first else { return nil }

        let coverPath = Self.comicInfoPath(in: filenames).flatMap { infoPath in
            try? archive.extractData(fromFile: infoPath)
        }.flatMap { data in
            ComicInfoCoverParser.frontCoverIndex(from: data)
        }.flatMap { index in
            imagePaths.indices.contains(index) ? imagePaths[index] : nil
        } ?? firstImage

        let data = try archive.extractData(fromFile: coverPath)
        return UIImage(data: data)
    }

    // MARK: - Helpers

    private static func comicInfoPath(in paths: [String]) -> String? {
        if paths.contains("ComicInfo.xml") {
            return "ComicInfo.xml"
        }

        return paths.first { path in
            let normalizedPath = path.replacingOccurrences(of: "\\", with: "/")
            let name = (normalizedPath as NSString).lastPathComponent
            return !normalizedPath.contains("__MACOSX/")
                && name.caseInsensitiveCompare("ComicInfo.xml") == .orderedSame
        }
    }

    private static func isImagePath(_ path: String) -> Bool {
        let normalizedPath = path.replacingOccurrences(of: "\\", with: "/")
        let name = (normalizedPath as NSString).lastPathComponent

        // Ignore hidden files and macOS metadata folders.
        if name.hasPrefix(".") || normalizedPath.contains("__MACOSX/") { return false }

        let ext = (name as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }
}
