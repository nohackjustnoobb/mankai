//
//  AppDirBookPlugin.swift
//  mankai
//
//  Created by Travis XU on 13/7/2026.
//

import Foundation

class AppDirBookPlugin: BookPlugin {
    static var shared = AppDirBookPlugin()

    private init() {
        let fileManager = FileManager.default
        let mangaDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("books")

        if !fileManager.fileExists(atPath: mangaDir.path) {
            try! fileManager.createDirectory(at: mangaDir, withIntermediateDirectories: true)
        }

        Logger.appDirBookPlugin.info(
            "AppDirBookPlugin initialized with PATH: \(mangaDir.path(percentEncoded: false))"
        )

        super.init(url: mangaDir, id: "mankai.books")
    }

    override var shouldSync: Bool {
        false
    }

    override var name: String? {
        String(localized: "localDir")
    }

    override var systemImageName: String? {
        "iphone"
    }

    /// Built-in plugin, do nothing
    override func savePlugin() throws {}

    /// Built-in plugin, do nothing
    override func deletePlugin() throws {}
}
