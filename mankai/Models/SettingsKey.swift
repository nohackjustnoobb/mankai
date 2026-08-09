//
//  SettingsKey.swift
//  mankai
//
//  Created by Travis XU on 27/6/2025.
//

import Foundation

enum SettingsKey: String {
    case hideBuiltInPlugins
    case showDebugScreen
    case downsampleImages

    /// Cache Settings
    case inMemoryCacheItemCount
    case diskCacheSizeLimit

    // Shared Reader Settings
    case readerType
    case imageLayout
    case respectMangaReadingDirection
    case useSmartGrouping
    case smartGroupingSensitivity

    // Continuous Reader
    case CR_readingDirection
    case CR_tapNavigation
    case CR_snapToPage
    case CR_softSnap

    // Paged Reader
    case PR_navigationOrientation
    case PR_readingDirection
    case PR_tapNavigation
    case PR_tapNavigationBehavior
}

enum ReaderType: Int {
    case continuous = 1
    case paged = 2
}

enum ImageLayout: Int {
    case auto = 1
    case onePerRow = 2
    case twoPerRow = 3
}

enum ReadingDirection: Int, Codable {
    case leftToRight = 1
    case rightToLeft = 2
    case vertical = 3
}

enum TapBehavior: Int {
    case previousNext = 1  // Left = previous, Right = next
    case followReadingDirection = 2  // Follow reading direction
}

enum NavigationOrientation: Int {
    case horizontal = 1
    case vertical = 2
}

enum DiskCacheLimit: Int {
    case fiveHundredMB = 500
    case oneGB = 1024
    case twoGB = 2048
    case fiveGB = 5120
    case tenGB = 10240
}
