//
//  ComicInfoCoverParser.swift
//  mankaiThumbnail
//
//  Created by Travis XU on 1/8/2026.
//

import Foundation
import SWXMLHash

enum ComicInfoCoverParser {
    static func frontCoverIndex(from data: Data) -> Int? {
        let document = XMLHash.config { config in
            config.detectParsingErrors = true
        }.parse(data)

        return frontCoverIndex(in: document)
    }

    private static func frontCoverIndex(in document: XMLIndexer) -> Int? {
        var result: Int?

        for child in document.children {
            guard let element = child.element else { continue }

            if element.name == "Pages" {
                result = frontCoverIndex(inPages: child) ?? result
            } else {
                result = frontCoverIndex(in: child) ?? result
            }
        }

        return result
    }

    private static func frontCoverIndex(inPages pages: XMLIndexer) -> Int? {
        var result: Int?

        for child in pages.children {
            guard let element = child.element else { continue }

            if element.name == "Page",
                element.attribute(by: "Type")?.text == "FrontCover",
                let image = element.attribute(by: "Image")?.text,
                let index = Int(image)
            {
                result = index
            }

            result = frontCoverIndex(inPages: child) ?? result
        }

        return result
    }
}
