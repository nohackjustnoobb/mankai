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
    static let downsampleImages: Bool = true
    static let checkClipboard: Bool = false
    static let browseViewMode: BrowseViewMode = .list

    // Cache Settings
    static let inMemoryCacheItemCount: Int = 100
    static let diskCacheSizeLimit: DiskCacheLimit = .oneGB

    // Shared Reader Settings
    static let imageLayout: ImageLayout = .auto
    static let respectMangaReadingDirection: Bool = true
    static let smartGrouping: Bool = false
    static let smartGroupingSensitivity: Double = 0.5

    /// Default Reader
    static var readerType: ReaderType { UIDevice.isIPad ? .paged : .continuous }

    // Continuous Reader Defaults
    static let CR_readingDirection: ReadingDirection = .rightToLeft
    static let CR_tapNavigation: Bool = true
    static let CR_snapToPage: Bool = false
    static let CR_softSnap: Bool = false

    // Paged Reader Defaults
    static let PR_navigationOrientation: NavigationOrientation = .vertical
    static let PR_pageTransition: PageTransition = .scroll
    static let PR_readingDirection: ReadingDirection = .rightToLeft
    static let PR_tapNavigation: Bool = true
    static let PR_tapNavigationBehavior: TapBehavior = .followReadingDirection
}
