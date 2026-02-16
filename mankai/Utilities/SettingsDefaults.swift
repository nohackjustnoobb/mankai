//
//  SettingsDefaults.swift
//  mankai
//
//  Created by Travis XU on 29/1/2026.
//

import Foundation
import UIKit

enum SettingsDefaults {
    static let hideBuiltInPlugins: Bool = false
    static let showDebugScreen: Bool = false

    // Cache Settings
    static let inMemoryCacheExpiryDuration: CacheDuration = .oneHour
    static let diskCacheSizeLimit: DiskCacheLimit = .oneGB

    /// Default Reader
    static var readerType: ReaderType {
        UIDevice.isIPad ? .paged : .continuous
    }

    static let imageLayout: ImageLayout = .auto
    static let useSmartGrouping: Bool = false
    static let smartGroupingSensitivity: Double = 0.5

    // Continuous Reader Defaults
    static let CR_readingDirection: ReadingDirection = .rightToLeft
    static let CR_tapNavigation: Bool = true
    static let CR_snapToPage: Bool = false
    static let CR_softSnap: Bool = false

    // Paged Reader Defaults
    static let PR_navigationOrientation: NavigationOrientation = .vertical
    static let PR_readingDirection: ReadingDirection = .rightToLeft
    static let PR_tapNavigation: Bool = true
    static let PR_tapNavigationBehavior: TapBehavior = .followReadingDirection
}
