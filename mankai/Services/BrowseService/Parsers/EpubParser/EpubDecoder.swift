//
//  EpubDecoder.swift
//  mankai
//
//  Created by Travis XU on 3/8/2026.
//

import Foundation
import ZIPFoundation

struct EpubPublication {
    let title: String?
    let credits: [String]
    let description: String?
    let subjects: [String]
    let modifiedAt: Date?
    let readingDirection: ReadingDirection?
    let coverPath: String?
    let pagePaths: [String]
}

enum EpubPackageDecoder {
    private static let containerPath = "META-INF/container.xml"
    private static let encryptionPath = "META-INF/encryption.xml"

    static func decode(archive: Archive) throws -> EpubPublication {
        let index = ArchiveIndex(archive: archive)
        let packageResource = try loadPackageResource(archive: archive, index: index)
        let encryptedPaths = try encryptedResourcePaths(archive: archive, index: index)
        try requireUnencrypted(packageResource, encryptedPaths: encryptedPaths)

        let packageData: Data
        do { packageData = try entryData(archive: archive, entry: packageResource.entry) } catch {
            throw MankaiErrorCode.browseEpubInvalidPackage.makeError(underlyingError: error)
        }

        guard let package = EpubXMLParsers.packageDocument(from: packageData) else {
            throw MankaiErrorCode.browseEpubInvalidPackage.makeError()
        }

        let resolver = EpubResourceResolver(
            archive: archive, index: index, packagePath: packageResource.normalizedPath,
            package: package, encryptedPaths: encryptedPaths)
        let cover = try resolver.coverResource()
        let pages = try resolver.pageResources(excluding: cover)

        guard !pages.isEmpty else { throw MankaiErrorCode.browseEpubNoReadableImages.makeError() }

        return EpubPublication(
            title: package.selectedTitle, credits: uniqueNonEmptyStrings(package.credits),
            description: firstNonEmpty(package.descriptions),
            subjects: uniqueNonEmptyStrings(package.subjects),
            modifiedAt: firstParsedDate(package.modifiedValues)
                ?? firstParsedDate(package.dateValues),
            readingDirection: readingDirection(from: package.pageProgressionDirection),
            coverPath: (cover ?? pages.first)?.entry.path, pagePaths: pages.map(\.entry.path))
    }

    private static func loadPackageResource(archive: Archive, index: ArchiveIndex) throws
        -> ArchiveResource
    {
        guard let container = index.resource(at: containerPath) else {
            throw MankaiErrorCode.browseEpubInvalidContainer.makeError()
        }

        let containerData: Data
        do { containerData = try entryData(archive: archive, entry: container.entry) } catch {
            throw MankaiErrorCode.browseEpubInvalidContainer.makeError(underlyingError: error)
        }

        guard let rootfileReference = EpubXMLParsers.containerRootfile(from: containerData),
            let rootfilePath = EpubPath.resolve(reference: rootfileReference, relativeTo: ""),
            let packageResource = index.resource(at: rootfilePath)
        else { throw MankaiErrorCode.browseEpubInvalidPackage.makeError() }
        return packageResource
    }

    private static func encryptedResourcePaths(archive: Archive, index: ArchiveIndex) throws -> Set<
        String
    > {
        guard let encryption = index.resource(at: encryptionPath) else { return [] }

        let data: Data
        do { data = try entryData(archive: archive, entry: encryption.entry) } catch {
            throw MankaiErrorCode.browseEpubInvalidPackage.makeError(underlyingError: error)
        }
        guard let references = EpubXMLParsers.encryptedResourceReferences(from: data) else {
            throw MankaiErrorCode.browseEpubInvalidPackage.makeError()
        }
        return Set(
            references.compactMap {
                EpubPath.resolve(reference: $0, relativeTo: "").map(EpubPath.key)
            })
    }

    private static func readingDirection(from value: String?) -> ReadingDirection? {
        switch value?.lowercased() { case "ltr": return .leftToRight case "rtl": return .rightToLeft
            default: return nil
        }
    }

    private static func uniqueNonEmptyStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    private static func firstNonEmpty(_ values: [String]) -> String? {
        values.lazy.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
        else { return nil }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) { return date }

        let internetFormatter = ISO8601DateFormatter()
        internetFormatter.formatOptions = [.withInternetDateTime]
        if let date = internetFormatter.date(from: value) { return date }

        for format in ["yyyy-MM-dd", "yyyy-MM", "yyyy"] {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .iso8601)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func firstParsedDate(_ values: [String]) -> Date? {
        values.lazy.compactMap(parseDate).first
    }

    private static func entryData(archive: Archive, entry: Entry) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry, consumer: { chunk in data.append(chunk) })
        return data
    }
}

private struct EpubResourceResolver {
    private let archive: Archive
    private let index: ArchiveIndex
    private let packagePath: String
    private let package: EpubPackageDocument
    private let encryptedPaths: Set<String>
    private let manifestById: [String: EpubManifestItem]
    private let manifestByPath: [String: EpubManifestItem]

    init(
        archive: Archive, index: ArchiveIndex, packagePath: String, package: EpubPackageDocument,
        encryptedPaths: Set<String>
    ) {
        self.archive = archive
        self.index = index
        self.packagePath = packagePath
        self.package = package
        self.encryptedPaths = encryptedPaths

        manifestById = package.manifest.reduce(into: [:]) { result, item in
            if result[item.id] == nil { result[item.id] = item }
        }
        manifestByPath = package.manifest.reduce(into: [:]) { result, item in
            guard let resolved = EpubPath.resolve(reference: item.href, relativeTo: packagePath)
            else { return }
            let key = EpubPath.key(resolved)
            if result[key] == nil { result[key] = item }
        }
    }

    func coverResource() throws -> ArchiveResource? {
        if let coverItem = package.manifest.first(where: { $0.properties.contains("cover-image") }),
            let cover = try imageResources(for: coverItem).first
        {
            return cover
        }

        if let legacyCoverId = package.legacyCoverId, let coverItem = manifestById[legacyCoverId],
            let cover = try imageResources(for: coverItem).first
        {
            return cover
        }

        if let guideCoverReference = package.guideCoverHref {
            return try imageResources(
                reference: guideCoverReference, relativeTo: packagePath, manifestItem: nil
            )
            .first
        }

        return nil
    }

    func pageResources(excluding cover: ArchiveResource?) throws -> [ArchiveResource] {
        var spinePages: [ArchiveResource] = []
        for idref in package.spineItemIds {
            guard let item = manifestById[idref] else { continue }
            try spinePages.append(contentsOf: imageResources(for: item))
        }
        if !spinePages.isEmpty { return spinePages }

        var seen = Set<String>()
        return try package.manifest.compactMap { item in
            guard let resolved = EpubPath.resolve(reference: item.href, relativeTo: packagePath),
                EpubResourceKind.isRaster(item: item, path: resolved)
            else { return nil }

            guard let resource = index.resource(at: resolved) else {
                throw resourceNotFound(path: resolved)
            }
            guard resource.normalizedPath != cover?.normalizedPath,
                seen.insert(EpubPath.key(resource.normalizedPath)).inserted
            else { return nil }

            try requireUnencrypted(resource, encryptedPaths: encryptedPaths)
            return resource
        }
    }

    private func imageResources(for item: EpubManifestItem) throws -> [ArchiveResource] {
        try imageResources(reference: item.href, relativeTo: packagePath, manifestItem: item)
    }

    private func imageResources(
        reference: String, relativeTo basePath: String, manifestItem: EpubManifestItem?
    ) throws -> [ArchiveResource] {
        guard let resolved = EpubPath.resolve(reference: reference, relativeTo: basePath) else {
            return []
        }

        let item = manifestItem ?? manifestByPath[EpubPath.key(resolved)]
        guard
            EpubResourceKind.isRaster(item: item, path: resolved)
                || EpubResourceKind.isContentDocument(item: item, path: resolved)
        else { return [] }

        guard let resource = index.resource(at: resolved) else {
            throw resourceNotFound(path: resolved)
        }
        try requireUnencrypted(resource, encryptedPaths: encryptedPaths)

        if EpubResourceKind.isRaster(item: item, path: resource.normalizedPath) {
            return [resource]
        }
        guard EpubResourceKind.isContentDocument(item: item, path: resource.normalizedPath) else {
            return []
        }

        guard let data = try? entryData(entry: resource.entry),
            let references = EpubXMLParsers.contentImageReferences(from: data)
        else { return [] }

        return try references.compactMap { reference in
            try rasterResource(reference: reference, relativeTo: resource.normalizedPath)
        }
    }

    private func rasterResource(reference: String, relativeTo basePath: String) throws
        -> ArchiveResource?
    {
        guard let path = EpubPath.resolve(reference: reference, relativeTo: basePath) else {
            return nil
        }

        let item = manifestByPath[EpubPath.key(path)]
        guard EpubResourceKind.isRaster(item: item, path: path) else { return nil }
        guard let resource = index.resource(at: path) else { throw resourceNotFound(path: path) }
        try requireUnencrypted(resource, encryptedPaths: encryptedPaths)
        return resource
    }

    private func entryData(entry: Entry) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry, consumer: { chunk in data.append(chunk) })
        return data
    }
}

private enum EpubResourceKind {
    private static let rasterExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "tif"
    ]
    private static let rasterMediaTypes: Set<String> = [
        "image/jpeg", "image/jpg", "image/png", "image/gif", "image/webp", "image/bmp",
        "image/x-bmp", "image/x-ms-bmp", "image/tiff"
    ]
    private static let contentDocumentMediaTypes: Set<String> = [
        "application/xhtml+xml", "text/html", "image/svg+xml"
    ]

    static func isRaster(item: EpubManifestItem?, path: String) -> Bool {
        let mediaType = item?.mediaType.lowercased() ?? ""
        if rasterMediaTypes.contains(mediaType) { return true }
        return rasterExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    static func isContentDocument(item: EpubManifestItem?, path: String) -> Bool {
        let mediaType = item?.mediaType.lowercased() ?? ""
        if contentDocumentMediaTypes.contains(mediaType) { return true }
        return ["xhtml", "html", "htm", "svg"]
            .contains((path as NSString).pathExtension.lowercased())
    }
}

private enum EpubPath {
    static func resolve(reference: String, relativeTo basePath: String) -> String? {
        var reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else { return nil }

        if let delimiter = reference.firstIndex(where: { $0 == "#" || $0 == "?" }) {
            reference = String(reference[..<delimiter])
        }
        guard !reference.isEmpty, let decoded = reference.removingPercentEncoding else {
            return nil
        }

        let normalizedReference = decoded.replacingOccurrences(of: "\\", with: "/")
        guard !normalizedReference.hasPrefix("/") else { return nil }
        if hasURIScheme(normalizedReference) { return nil }

        var components = basePath.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if !basePath.isEmpty, !components.isEmpty { components.removeLast() }

        for component in normalizedReference.split(separator: "/", omittingEmptySubsequences: true)
        {
            switch component { case ".": continue case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
                default:
                    let value = String(component)
                    guard !value.contains("\0") else { return nil }
                    components.append(value)
            }
        }

        guard !components.isEmpty else { return nil }
        return components.joined(separator: "/")
    }

    static func normalizeArchivePath(_ path: String) -> String? {
        let path = path.replacingOccurrences(of: "\\", with: "/")
        guard !path.hasPrefix("/") else { return nil }

        var components: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component { case ".": continue case "..": return nil default:
                components.append(String(component))
            }
        }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: "/")
    }

    static func key(_ path: String) -> String { path.precomposedStringWithCanonicalMapping }

    private static func hasURIScheme(_ value: String) -> Bool {
        guard let colon = value.firstIndex(of: ":"), colon != value.startIndex else { return false }

        let scheme = value[..<colon].unicodeScalars
        guard let first = scheme.first, isASCIIAlpha(first) else { return false }
        return scheme.dropFirst()
            .allSatisfy { scalar in
                isASCIIAlpha(scalar) || (48...57).contains(scalar.value) || scalar == "+"
                    || scalar == "-" || scalar == "."
            }
    }

    private static func isASCIIAlpha(_ scalar: Unicode.Scalar) -> Bool {
        (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }
}

private struct ArchiveResource {
    let entry: Entry
    let normalizedPath: String
}

private struct ArchiveIndex {
    private let resources: [String: ArchiveResource]

    init(archive: Archive) {
        var resources: [String: ArchiveResource] = [:]
        for entry in archive where entry.type == .file {
            guard let normalizedPath = EpubPath.normalizeArchivePath(entry.path) else { continue }
            let key = EpubPath.key(normalizedPath)
            if resources[key] == nil {
                resources[key] = ArchiveResource(entry: entry, normalizedPath: normalizedPath)
            }
        }
        self.resources = resources
    }

    func resource(at path: String) -> ArchiveResource? {
        guard let normalizedPath = EpubPath.normalizeArchivePath(path) else { return nil }
        return resources[EpubPath.key(normalizedPath)]
    }
}

private func requireUnencrypted(_ resource: ArchiveResource, encryptedPaths: Set<String>) throws {
    guard !encryptedPaths.contains(EpubPath.key(resource.normalizedPath)) else {
        throw MankaiErrorCode.browseEpubProtectedContent.makeError()
    }
}

private func resourceNotFound(path: String) -> NSError {
    Logger.epubParser.error("EPUB resource not found: \(path)")
    return MankaiErrorCode.browseEpubResourceNotFound.makeError()
}

struct EpubManifestItem {
    let id: String
    let href: String
    let mediaType: String
    let properties: Set<String>
}

struct EpubTextValue {
    let id: String?
    let value: String
}

struct EpubMetaValue {
    let property: String
    let refines: String?
    let value: String
}

struct EpubPackageDocument {
    var titles: [EpubTextValue] = []
    var credits: [String] = []
    var descriptions: [String] = []
    var subjects: [String] = []
    var dateValues: [String] = []
    var metaValues: [EpubMetaValue] = []
    var manifest: [EpubManifestItem] = []
    var spineItemIds: [String] = []
    var pageProgressionDirection: String?
    var legacyCoverId: String?
    var guideCoverHref: String?
    var sawManifest = false
    var sawSpine = false

    var selectedTitle: String? {
        for meta in metaValues
        where meta.property.lowercased().hasSuffix("title-type")
            && meta.value.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("main") == .orderedSame
        {
            guard let refines = meta.refines, refines.hasPrefix("#") else { continue }
            let id = String(refines.dropFirst())
            if let title = titles.first(where: { $0.id == id })?.value,
                !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return titles.lazy.map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    var modifiedValues: [String] {
        metaValues.compactMap { $0.property.lowercased() == "dcterms:modified" ? $0.value : nil }
    }
}
