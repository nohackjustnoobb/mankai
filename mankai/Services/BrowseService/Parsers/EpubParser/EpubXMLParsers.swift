//
//  EpubXMLParsers.swift
//  mankai
//
//  Created by Travis XU on 3/8/2026.
//

import Foundation
import SWXMLHash

enum EpubXMLParsers {
    static func containerRootfile(from data: Data) -> String? {
        let document = EpubXML.parse(data)
        guard EpubXML.hasRootElement(document) else { return nil }
        return EpubContainerParser().parse(document)
    }

    static func packageDocument(from data: Data) -> EpubPackageDocument? {
        let document = EpubXML.parse(data)
        guard EpubXML.hasRootElement(document) else { return nil }

        var parser = EpubPackageParser()
        let package = parser.parse(document)
        guard package.sawManifest, package.sawSpine else { return nil }
        return package
    }

    static func contentImageReferences(from data: Data) -> [String]? {
        let document = EpubXML.parse(data)
        guard EpubXML.hasRootElement(document) else { return nil }
        var parser = EpubContentImageParser()
        return parser.parse(document)
    }

    static func encryptedResourceReferences(from data: Data) -> [String]? {
        let document = EpubXML.parse(data)
        guard EpubXML.hasRootElement(document) else { return nil }
        var parser = EpubEncryptionParser()
        return parser.parse(document)
    }
}

private enum EpubXML {
    static func parse(_ data: Data) -> XMLIndexer {
        XMLHash.config { config in
            config.detectParsingErrors = true
            config.shouldProcessNamespaces = true
        }
        .parse(data)
    }

    static func hasRootElement(_ document: XMLIndexer) -> Bool { !document.children.isEmpty }

    static func localName(_ node: XMLIndexer) -> String { localName(node.element?.name ?? "") }

    static func localName(_ name: String) -> String {
        String(name.split(separator: ":").last ?? Substring(name)).lowercased()
    }

    static func attribute(_ node: XMLIndexer, named name: String) -> String? {
        guard let element = node.element else { return nil }

        if let value = element.attribute(by: name)?.text { return value }

        return element.allAttributes.values.first {
            localName($0.name).caseInsensitiveCompare(name) == .orderedSame
        }?
        .text
    }

    static func text(_ node: XMLIndexer) -> String { node.element?.recursiveText ?? "" }
}

private struct EpubContainerParser {
    func parse(_ document: XMLIndexer) -> String? { rootfile(in: document) }

    private func rootfile(in document: XMLIndexer) -> String? {
        for child in document.children {
            if EpubXML.localName(child) == "rootfile",
                let path = EpubXML.attribute(child, named: "full-path"),
                !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return path
            }

            if let path = rootfile(in: child) { return path }
        }
        return nil
    }
}

private struct EpubPackageParser {
    private enum Section { case metadata, manifest, spine, guide }

    private var document = EpubPackageDocument()

    mutating func parse(_ xml: XMLIndexer) -> EpubPackageDocument {
        visit(xml, in: nil)
        return document
    }

    private mutating func visit(_ xml: XMLIndexer, in section: Section?) {
        for child in xml.children { visitElement(child, in: section) }
    }

    private mutating func visitElement(_ element: XMLIndexer, in section: Section?) {
        let name = EpubXML.localName(element)

        switch name { case "metadata": visit(element, in: .metadata) case "manifest":
            document.sawManifest = true
            visit(element, in: .manifest)
            case "spine":
                document.sawSpine = true
                document.pageProgressionDirection = EpubXML.attribute(
                    element, named: "page-progression-direction")
                visit(element, in: .spine)
            case "guide": visit(element, in: .guide)
            default: visitSectionElement(element, name: name, in: section)
        }
    }

    private mutating func visitSectionElement(
        _ element: XMLIndexer, name: String, in section: Section?
    ) {
        switch section { case .metadata:
            if captureMetadata(element, name: name) { return }
            visit(element, in: .metadata)
            case .manifest where name == "item":
                guard let id = EpubXML.attribute(element, named: "id"),
                    let href = EpubXML.attribute(element, named: "href"), !id.isEmpty, !href.isEmpty
                else { return }

                let mediaType = EpubXML.attribute(element, named: "media-type") ?? ""
                let properties = Set(
                    (EpubXML.attribute(element, named: "properties") ?? "")
                        .split(whereSeparator: \.isWhitespace).map { $0.lowercased() })
                document.manifest.append(
                    EpubManifestItem(
                        id: id, href: href, mediaType: mediaType, properties: properties))
            case .spine where name == "itemref":
                if let idref = EpubXML.attribute(element, named: "idref"), !idref.isEmpty {
                    document.spineItemIds.append(idref)
                }
            case .guide where name == "reference":
                let types = (EpubXML.attribute(element, named: "type") ?? "")
                    .split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
                if document.guideCoverHref == nil, types.contains("cover"),
                    let href = EpubXML.attribute(element, named: "href"), !href.isEmpty
                {
                    document.guideCoverHref = href
                }
            default: visit(element, in: section)
        }
    }

    private mutating func captureMetadata(_ element: XMLIndexer, name: String) -> Bool {
        let id = EpubXML.attribute(element, named: "id")

        switch name { case "title":
            let value = EpubXML.text(element).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { document.titles.append(EpubTextValue(id: id, value: value)) }
            case "creator", "contributor":
                appendNonEmpty(EpubXML.text(element), to: &document.credits)
            case "description": appendNonEmpty(EpubXML.text(element), to: &document.descriptions)
            case "subject": appendNonEmpty(EpubXML.text(element), to: &document.subjects)
            case "date": appendNonEmpty(EpubXML.text(element), to: &document.dateValues)
            case "meta":
                let legacyName = EpubXML.attribute(element, named: "name")
                let legacyContent = EpubXML.attribute(element, named: "content")
                if document.legacyCoverId == nil,
                    legacyName?.caseInsensitiveCompare("cover") == .orderedSame, let legacyContent,
                    !legacyContent.isEmpty
                {
                    document.legacyCoverId = legacyContent
                }

                if let property = EpubXML.attribute(element, named: "property"), !property.isEmpty {
                    let value = EpubXML.text(element)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty {
                        document.metaValues.append(
                            EpubMetaValue(
                                property: property,
                                refines: EpubXML.attribute(element, named: "refines"), value: value)
                        )
                    }
                }
            default: return false
        }

        return true
    }

    private func appendNonEmpty(_ value: String, to values: inout [String]) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { values.append(trimmed) }
    }
}

private struct EpubContentImageParser {
    private var references: [String] = []

    mutating func parse(_ document: XMLIndexer) -> [String] {
        visit(document)
        return references
    }

    private mutating func visit(_ document: XMLIndexer) {
        for child in document.children {
            switch EpubXML.localName(child) { case "img":
                if let src = EpubXML.attribute(child, named: "src"), !src.isEmpty {
                    references.append(src)
                }
                case "image":
                    if let href = EpubXML.attribute(child, named: "href"), !href.isEmpty {
                        references.append(href)
                    }
                default: break
            }
            visit(child)
        }
    }
}

private struct EpubEncryptionParser {
    private var references: [String] = []

    mutating func parse(_ document: XMLIndexer) -> [String] {
        visit(document, insideEncryptedData: false)
        return references
    }

    private mutating func visit(_ document: XMLIndexer, insideEncryptedData: Bool) {
        for child in document.children {
            let name = EpubXML.localName(child)
            let isInsideEncryptedData = insideEncryptedData || name == "encrypteddata"

            if name == "cipherreference", isInsideEncryptedData,
                let uri = EpubXML.attribute(child, named: "uri"), !uri.isEmpty
            {
                references.append(uri)
            }

            visit(child, insideEncryptedData: isInsideEncryptedData)
        }
    }
}
