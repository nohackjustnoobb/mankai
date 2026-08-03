//
//  AppDirBrowsablePlugin.swift
//  mankai
//
//  Created by Travis XU on 13/7/2026.
//

import Foundation
import SwiftUI

final class AppDirBrowsablePlugin: FsBrowsablePlugin {
    static let shared = AppDirBrowsablePlugin()

    private init() {
        let fileManager = FileManager.default
        let mangaDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("books")

        if !fileManager.fileExists(atPath: mangaDir.path) {
            do {
                try fileManager.createDirectory(at: mangaDir, withIntermediateDirectories: true)
            } catch {
                Logger.appDirBrowsablePlugin.error("Failed to create directory \(mangaDir.path): \(error)")
            }
        }

        Logger.appDirBrowsablePlugin.info(
            "AppDirBrowsablePlugin initialized with PATH: \(mangaDir.path(percentEncoded: false))"
        )

        super.init(url: mangaDir, id: "mankai.books")
    }

    override var shouldSync: Bool {
        false
    }

    override var name: String? {
        String(localized: "localDir")
    }

    override var systemImageName: String {
        "iphone"
    }

    override var systemImageColor: Color {
        .accentColor
    }

    /// Built-in plugin, do nothing
    override func savePlugin() throws {}

    /// Built-in plugin, do nothing
    override func deletePlugin() throws {}
}
