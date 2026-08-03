//
//  FsParserFile.swift
//  mankai
//
//  Created by Travis XU on 3/8/2026.
//

import Foundation

struct FsParserFile: ParserFile {
    let cacheKey: String
    let url: URL

    var fileName: String {
        url.lastPathComponent
    }

    func getContent() async throws -> Data {
        try Data(contentsOf: url)
    }

    func getUrl() async throws -> URL {
        url
    }
}
