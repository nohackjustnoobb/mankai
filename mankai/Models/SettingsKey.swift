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

    /// Cache Settings
    case inMemoryCacheExpiryDuration
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
    case previousNext = 1 // Left = previous, Right = next
    case followReadingDirection = 2 // Follow reading direction
}

enum NavigationOrientation: Int {
    case horizontal = 1
    case vertical = 2
}

enum CacheDuration: Double {
    case auto = 0 // Use default
    case fifteenMinutes = 900 // 15 minutes
    case thirtyMinutes = 1800 // 30 minutes
    case oneHour = 3600 // 1 hour
    case twoHours = 7200 // 2 hours
    case sixHours = 21600 // 6 hours
    case twelveHours = 43200 // 12 hours
    case oneDay = 86400 // 24 hours
}

enum DiskCacheLimit: Int {
    case fiveHundredMB = 500
    case oneGB = 1024
    case twoGB = 2048
    case fiveGB = 5120
    case tenGB = 10240
}
