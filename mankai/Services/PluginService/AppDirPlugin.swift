//
//  AppDirPlugin.swift
//  mankai
//
//  Created by Travis XU on 1/7/2025.
//

import Foundation

class AppDirPlugin: ReadWriteFsPlugin {
    static var shared = AppDirPlugin()

    private init() {
        let fileManager = FileManager.default
        let mangaDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("mangas")

        if !fileManager.fileExists(atPath: mangaDir.path) {
            try! fileManager.createDirectory(at: mangaDir, withIntermediateDirectories: true)
        }

        Logger.appDirPlugin.info(
            "AppDirPlugin initialized with PATH: \(mangaDir.path(percentEncoded: false))"
        )

        super.init(url: mangaDir, id: "mankai")
    }

    override var tags: [String] {
        [
            String(localized: "builtin"),
            String(localized: "fs"),
            String(localized: "editable"),
        ]
    }

    override var description: String? {
        String(localized: "appFsPluginDescription")
    }

    override var name: String? {
        String(localized: "appName")
    }

    override var shouldSync: Bool {
        false
    }

    /// Built-in plugin, do nothing
    override func savePlugin() throws {}

    /// Built-in plugin, do nothing
    override func deletePlugin() throws {}
}
