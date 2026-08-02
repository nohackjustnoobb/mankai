//
//  ComicInfoCoverParser.swift
//  mankaiThumbnail
//
//  Created by Travis XU on 1/8/2026.
//

import Foundation

enum ComicInfoCoverParser {
    static func frontCoverIndex(from data: Data) -> Int? {
        let parser = XMLParser(data: data)
        let delegate = Delegate()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false

        guard parser.parse() else { return nil }
        return delegate.frontCoverIndex
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var frontCoverIndex: Int?
        private var inPages = false

        func parser(
            _: XMLParser,
            didStartElement elementName: String,
            namespaceURI _: String?,
            qualifiedName _: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            if elementName == "Pages" {
                inPages = true
                return
            }

            guard inPages,
                  elementName == "Page",
                  attributeDict["Type"] == "FrontCover",
                  let image = attributeDict["Image"],
                  let index = Int(image)
            else { return }

            frontCoverIndex = index
        }

        func parser(
            _: XMLParser,
            didEndElement elementName: String,
            namespaceURI _: String?,
            qualifiedName _: String?
        ) {
            if elementName == "Pages" {
                inPages = false
            }
        }
    }
}
