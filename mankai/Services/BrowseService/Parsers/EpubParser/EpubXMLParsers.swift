//
//  EpubXMLParsers.swift
//  mankai
//
//  Created by Travis XU on 3/8/2026.
//

import Foundation

enum EpubXMLParsers {
    static func containerRootfile(from data: Data) -> String? {
        EpubContainerXMLParser.parse(data: data)
    }

    static func packageDocument(from data: Data) -> EpubPackageDocument? {
        EpubPackageXMLParser.parse(data: data)
    }

    static func contentImageReferences(from data: Data) -> [String]? {
        EpubContentImageXMLParser.parse(data: data)
    }

    static func encryptedResourceReferences(from data: Data) -> [String]? {
        EpubEncryptionXMLParser.parse(data: data)
    }
}

private enum EpubXML {
    static func localName(_ elementName: String, qualifiedName: String?) -> String {
        let name = qualifiedName ?? elementName
        return String(name.split(separator: ":").last ?? Substring(name)).lowercased()
    }

    static func attribute(_ attributes: [String: String], named name: String) -> String? {
        attributes.first { key, _ in
            String(key.split(separator: ":").last ?? Substring(key))
                .caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }

    static func parser(data: Data, delegate: XMLParserDelegate) -> XMLParser {
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        return parser
    }
}

private final class EpubContainerXMLParser: NSObject, XMLParserDelegate {
    private var rootfile: String?

    static func parse(data: Data) -> String? {
        let delegate = EpubContainerXMLParser()
        let parser = EpubXML.parser(data: data, delegate: delegate)
        guard parser.parse() else { return nil }
        return delegate.rootfile
    }

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard rootfile == nil,
            EpubXML.localName(elementName, qualifiedName: qName) == "rootfile",
            let path = EpubXML.attribute(attributeDict, named: "full-path"),
            !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        rootfile = path
    }
}

private final class EpubPackageXMLParser: NSObject, XMLParserDelegate {
    private enum Section {
        case metadata, manifest, spine, guide
    }

    private enum CaptureKind {
        case title, credit, description, subject, date, meta
    }

    private struct Capture {
        let kind: CaptureKind
        let id: String?
        let property: String?
        let refines: String?
        var depth: Int
        var text: String
    }

    private var document = EpubPackageDocument()
    private var section: Section?
    private var capture: Capture?

    static func parse(data: Data) -> EpubPackageDocument? {
        let delegate = EpubPackageXMLParser()
        let parser = EpubXML.parser(data: data, delegate: delegate)
        guard parser.parse(), delegate.document.sawManifest, delegate.document.sawSpine else {
            return nil
        }
        return delegate.document
    }

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if capture != nil {
            capture?.depth += 1
            return
        }

        let name = EpubXML.localName(elementName, qualifiedName: qName)
        switch name {
        case "metadata":
            section = .metadata
            return
        case "manifest":
            section = .manifest
            document.sawManifest = true
            return
        case "spine":
            section = .spine
            document.sawSpine = true
            document.pageProgressionDirection = EpubXML.attribute(
                attributeDict,
                named: "page-progression-direction"
            )
            return
        case "guide":
            section = .guide
            return
        default:
            break
        }

        switch section {
        case .metadata:
            startMetadataCapture(name: name, attributes: attributeDict)
        case .manifest where name == "item":
            guard let id = EpubXML.attribute(attributeDict, named: "id"),
                let href = EpubXML.attribute(attributeDict, named: "href"),
                !id.isEmpty,
                !href.isEmpty
            else { return }
            let mediaType = EpubXML.attribute(attributeDict, named: "media-type") ?? ""
            let properties = Set(
                (EpubXML.attribute(attributeDict, named: "properties") ?? "")
                    .split(whereSeparator: \.isWhitespace)
                    .map { $0.lowercased() }
            )
            document.manifest.append(
                EpubManifestItem(
                    id: id,
                    href: href,
                    mediaType: mediaType,
                    properties: properties
                )
            )
        case .spine where name == "itemref":
            if let idref = EpubXML.attribute(attributeDict, named: "idref"), !idref.isEmpty {
                document.spineItemIds.append(idref)
            }
        case .guide where name == "reference":
            let types = (EpubXML.attribute(attributeDict, named: "type") ?? "")
                .split(whereSeparator: \.isWhitespace)
                .map { $0.lowercased() }
            if document.guideCoverHref == nil,
                types.contains("cover"),
                let href = EpubXML.attribute(attributeDict, named: "href"),
                !href.isEmpty
            {
                document.guideCoverHref = href
            }
        default:
            break
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        capture?.text += string
    }

    func parser(_: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            capture?.text += string
        }
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName qName: String?
    ) {
        if capture != nil {
            capture?.depth -= 1
            if capture?.depth == 0, let completed = capture {
                finishCapture(completed)
                capture = nil
            }
            return
        }

        switch EpubXML.localName(elementName, qualifiedName: qName) {
        case "metadata", "manifest", "spine", "guide":
            section = nil
        default:
            break
        }
    }

    private func startMetadataCapture(name: String, attributes: [String: String]) {
        let id = EpubXML.attribute(attributes, named: "id")
        switch name {
        case "title":
            beginCapture(.title, id: id)
        case "creator", "contributor":
            beginCapture(.credit, id: id)
        case "description":
            beginCapture(.description, id: id)
        case "subject":
            beginCapture(.subject, id: id)
        case "date":
            beginCapture(.date, id: id)
        case "meta":
            let legacyName = EpubXML.attribute(attributes, named: "name")
            let legacyContent = EpubXML.attribute(attributes, named: "content")
            if document.legacyCoverId == nil,
                legacyName?.caseInsensitiveCompare("cover") == .orderedSame,
                let legacyContent,
                !legacyContent.isEmpty
            {
                document.legacyCoverId = legacyContent
            }

            if let property = EpubXML.attribute(attributes, named: "property"),
                !property.isEmpty
            {
                beginCapture(
                    .meta,
                    id: id,
                    property: property,
                    refines: EpubXML.attribute(attributes, named: "refines")
                )
            }
        default:
            break
        }
    }

    private func beginCapture(
        _ kind: CaptureKind,
        id: String?,
        property: String? = nil,
        refines: String? = nil
    ) {
        capture = Capture(
            kind: kind,
            id: id,
            property: property,
            refines: refines,
            depth: 1,
            text: ""
        )
    }

    private func finishCapture(_ capture: Capture) {
        let value = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        switch capture.kind {
        case .title:
            document.titles.append(EpubTextValue(id: capture.id, value: value))
        case .credit:
            document.credits.append(value)
        case .description:
            document.descriptions.append(value)
        case .subject:
            document.subjects.append(value)
        case .date:
            document.dateValues.append(value)
        case .meta:
            if let property = capture.property {
                document.metaValues.append(
                    EpubMetaValue(
                        property: property,
                        refines: capture.refines,
                        value: value
                    )
                )
            }
        }
    }
}

private final class EpubContentImageXMLParser: NSObject, XMLParserDelegate {
    private var references: [String] = []

    static func parse(data: Data) -> [String]? {
        let delegate = EpubContentImageXMLParser()
        let parser = EpubXML.parser(data: data, delegate: delegate)
        guard parser.parse() else { return nil }
        return delegate.references
    }

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch EpubXML.localName(elementName, qualifiedName: qName) {
        case "img":
            if let src = EpubXML.attribute(attributeDict, named: "src"), !src.isEmpty {
                references.append(src)
            }
        case "image":
            if let href = EpubXML.attribute(attributeDict, named: "href"), !href.isEmpty {
                references.append(href)
            }
        default:
            break
        }
    }
}

private final class EpubEncryptionXMLParser: NSObject, XMLParserDelegate {
    private var encryptedDataDepth = 0
    private var references: [String] = []

    static func parse(data: Data) -> [String]? {
        let delegate = EpubEncryptionXMLParser()
        let parser = EpubXML.parser(data: data, delegate: delegate)
        guard parser.parse() else { return nil }
        return delegate.references
    }

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = EpubXML.localName(elementName, qualifiedName: qName)
        if name == "encrypteddata" {
            encryptedDataDepth += 1
        } else if name == "cipherreference",
            encryptedDataDepth > 0,
            let uri = EpubXML.attribute(attributeDict, named: "uri"),
            !uri.isEmpty
        {
            references.append(uri)
        }
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName qName: String?
    ) {
        if EpubXML.localName(elementName, qualifiedName: qName) == "encrypteddata" {
            encryptedDataDepth = max(0, encryptedDataDepth - 1)
        }
    }
}
