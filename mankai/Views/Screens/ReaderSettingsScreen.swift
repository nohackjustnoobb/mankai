//
//  ReaderSettingsScreen.swift
//  mankai
//
//  Created by Travis XU on 12/7/2025.
//

import SwiftUI

struct ReaderSettingsScreen: View {
    @AppStorage(SettingsKey.readerType.rawValue) private var readerTypeRawValue: Int =
        SettingsDefaults.readerType.rawValue
    @AppStorage(SettingsKey.imageLayout.rawValue) private var imageLayoutRawValue: Int =
        SettingsDefaults.imageLayout.rawValue
    @AppStorage(SettingsKey.respectMangaReadingDirection.rawValue) private
        var respectMangaReadingDirection: Bool = SettingsDefaults.respectMangaReadingDirection
    @AppStorage(SettingsKey.downsampleImages.rawValue) private var downsampleImages: Bool =
        SettingsDefaults.downsampleImages
    @AppStorage(SettingsKey.downsampleAggressiveness.rawValue) private var downsampleAggressiveness:
        Double = SettingsDefaults.downsampleAggressiveness
    @AppStorage(SettingsKey.imageUpscaling.rawValue) private var imageUpscaling: Bool =
        SettingsDefaults.imageUpscaling
    @AppStorage(SettingsKey.upscaleThreshold.rawValue) private var upscaleThreshold: Double =
        SettingsDefaults.upscaleThreshold
    @AppStorage(SettingsKey.smartGrouping.rawValue) private var smartGrouping: Bool =
        SettingsDefaults.smartGrouping
    @AppStorage(SettingsKey.smartGroupingSensitivity.rawValue) private var smartGroupingSensitivity:
        Double = SettingsDefaults.smartGroupingSensitivity

    private var upscaleSensitivityLabel: LocalizedStringKey {
        switch upscaleThreshold { case ..<0.75: return "upscaleSensitivityVeryLow" case ..<1.25:
            return "upscaleSensitivityLow"
            case ..<1.75: return "upscaleSensitivityBalanced"
            case ..<2.25: return "upscaleSensitivityHigh"
            default: return "upscaleSensitivityMaximum"
        }
    }

    private var memorySavingsLabel: LocalizedStringKey {
        switch downsampleAggressiveness { case ..<0.25: return "downsampleMemorySavingsLow"
            case ..<0.75: return "downsampleMemorySavingsBalanced"
            default: return "downsampleMemorySavingsHigh"
        }
    }

    var body: some View {
        List {
            SettingsHeaderView(
                image: Image(systemName: "book.pages.fill"), color: .orange,
                title: String(localized: "reader"),
                description: String(localized: "readerDescription"))

            Section("readingMode") {
                Picker(
                    String(localized: "readerType"),
                    selection: Binding(
                        get: {
                            ReaderType(rawValue: readerTypeRawValue) ?? SettingsDefaults.readerType
                        }, set: { readerTypeRawValue = $0.rawValue })
                ) {
                    Text(ReaderType.paged.localizedName).tag(ReaderType.paged)
                    Text(ReaderType.continuous.localizedName).tag(ReaderType.continuous)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        String(localized: "respectMangaReadingDirection"),
                        isOn: $respectMangaReadingDirection)
                    Text("respectMangaReadingDirectionDescription").font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("imageProcessing") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("imageUpscaling", isOn: $imageUpscaling)
                    Text("imageUpscalingDescription").font(.caption).foregroundColor(.secondary)
                }

                if imageUpscaling {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("upscaleSensitivity")
                            Spacer()
                            Text(upscaleSensitivityLabel).foregroundColor(.secondary)
                        }
                        Slider(value: $upscaleThreshold, in: 0.5...2.5, step: 0.5) {
                            Text("upscaleSensitivity")
                        }
                        Text("upscaleSensitivityDescription").font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Toggle("downsampleImages", isOn: $downsampleImages)
                    Text("downsampleImagesDescription").font(.caption).foregroundColor(.secondary)
                }

                if downsampleImages {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("downsampleMemorySavings")
                            Spacer()
                            Text(memorySavingsLabel).foregroundColor(.secondary)
                        }
                        Slider(value: $downsampleAggressiveness, in: 0...1, step: 0.5) {
                            Text("downsampleMemorySavings")
                        }
                        Text("downsampleMemorySavingsDescription").font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("imageGrouping") {
                Picker(
                    String(localized: "imageLayout"),
                    selection: Binding(
                        get: {
                            ImageLayout(rawValue: imageLayoutRawValue)
                                ?? SettingsDefaults.imageLayout
                        }, set: { imageLayoutRawValue = $0.rawValue })
                ) {
                    Text(ImageLayout.auto.localizedName).tag(ImageLayout.auto)
                    Text(ImageLayout.onePerRow.localizedName).tag(ImageLayout.onePerRow)
                    Text(ImageLayout.twoPerRow.localizedName).tag(ImageLayout.twoPerRow)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Toggle(String(localized: "smartGrouping"), isOn: $smartGrouping)
                    Text("smartGroupingDescription").font(.caption).foregroundColor(.secondary)
                }

                if smartGrouping {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("smartGroupingSensitivity")
                        Slider(value: $smartGroupingSensitivity, in: 0...1, step: 0.1)
                        Text("smartGroupingSensitivityDescription").font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let readerType = ReaderType(rawValue: readerTypeRawValue) {
                switch readerType { case .continuous: ContinuousReaderSettingsView() case .paged:
                    PagedReaderSettingsView()
                }
            }
        }
        .navigationTitle("reader").navigationBarTitleDisplayMode(.inline)
        .onChange(of: imageUpscaling) { _, isEnabled in
            guard !isEnabled else { return }

            Task { await Upscaling.shared.unloadImmediately() }
        }
        .onChange(of: smartGrouping) { _, isEnabled in
            guard !isEnabled else { return }

            Task { await SmartGrouping.shared.unloadImmediately() }
        }
    }
}

struct ContinuousReaderSettingsView: View {
    @AppStorage(SettingsKey.CR_readingDirection.rawValue) private var readingDirectionRawValue:
        Int = SettingsDefaults.CR_readingDirection.rawValue
    @AppStorage(SettingsKey.CR_tapNavigation.rawValue) private var tapNavigation: Bool =
        SettingsDefaults.CR_tapNavigation
    @AppStorage(SettingsKey.CR_snapToPage.rawValue) private var snapToPage: Bool = SettingsDefaults
        .CR_snapToPage
    @AppStorage(SettingsKey.CR_softSnap.rawValue) private var softSnap: Bool = SettingsDefaults
        .CR_softSnap

    var body: some View {
        Section("continuousReaderSettings") {
            Picker(
                "readingDirection",
                selection: Binding(
                    get: {
                        ReadingDirection(rawValue: readingDirectionRawValue)
                            ?? SettingsDefaults.CR_readingDirection
                    }, set: { readingDirectionRawValue = $0.rawValue })
            ) {
                Text(ReadingDirection.leftToRight.localizedName).tag(ReadingDirection.leftToRight)
                Text(ReadingDirection.rightToLeft.localizedName).tag(ReadingDirection.rightToLeft)
            }

            Toggle(String(localized: "tapNavigation"), isOn: $tapNavigation)

            Toggle(String(localized: "snapToPage"), isOn: $snapToPage)

            if snapToPage { Toggle(String(localized: "softSnap"), isOn: $softSnap) }
        }
    }
}

struct PagedReaderSettingsView: View {
    @AppStorage(SettingsKey.PR_readingDirection.rawValue) private var readingDirectionRawValue:
        Int = SettingsDefaults.PR_readingDirection.rawValue
    @AppStorage(SettingsKey.PR_navigationOrientation.rawValue) private
        var navigationOrientationRawValue: Int = SettingsDefaults.PR_navigationOrientation.rawValue
    @AppStorage(SettingsKey.PR_pageTransition.rawValue) private var pageTransitionRawValue: Int =
        SettingsDefaults.PR_pageTransition.rawValue
    @AppStorage(SettingsKey.PR_tapNavigation.rawValue) private var tapNavigation: Bool =
        SettingsDefaults.PR_tapNavigation
    @AppStorage(SettingsKey.PR_tapNavigationBehavior.rawValue) private
        var tapNavigationBehaviorRawValue: Int = SettingsDefaults.PR_tapNavigationBehavior.rawValue

    private var isVertical: Bool {
        NavigationOrientation(rawValue: navigationOrientationRawValue) == .vertical
    }

    var body: some View {
        Section("pagedReaderSettings") {
            Picker(
                "navigationOrientation",
                selection: Binding(
                    get: {
                        NavigationOrientation(rawValue: navigationOrientationRawValue)
                            ?? SettingsDefaults.PR_navigationOrientation
                    }, set: { navigationOrientationRawValue = $0.rawValue })
            ) {
                Text(NavigationOrientation.horizontal.localizedName)
                    .tag(NavigationOrientation.horizontal)
                Text(NavigationOrientation.vertical.localizedName)
                    .tag(NavigationOrientation.vertical)
            }

            Picker(
                "pageTransition",
                selection: Binding(
                    get: {
                        PageTransition(rawValue: pageTransitionRawValue)
                            ?? SettingsDefaults.PR_pageTransition
                    }, set: { pageTransitionRawValue = $0.rawValue })
            ) {
                Text(PageTransition.scroll.localizedName).tag(PageTransition.scroll)
                Text(PageTransition.pageCurl.localizedName).tag(PageTransition.pageCurl)
            }

            Picker(
                "readingDirection",
                selection: Binding(
                    get: {
                        ReadingDirection(rawValue: readingDirectionRawValue)
                            ?? SettingsDefaults.PR_readingDirection
                    }, set: { readingDirectionRawValue = $0.rawValue })
            ) {
                Text(ReadingDirection.leftToRight.localizedName).tag(ReadingDirection.leftToRight)
                Text(ReadingDirection.rightToLeft.localizedName).tag(ReadingDirection.rightToLeft)
            }

            Toggle(String(localized: "tapNavigation"), isOn: $tapNavigation)

            if tapNavigation && !isVertical {
                Picker(
                    "tapNavigationBehavior",
                    selection: Binding(
                        get: {
                            TapBehavior(rawValue: tapNavigationBehaviorRawValue)
                                ?? SettingsDefaults.PR_tapNavigationBehavior
                        }, set: { tapNavigationBehaviorRawValue = $0.rawValue })
                ) {
                    Text(TapBehavior.previousNext.localizedName).tag(TapBehavior.previousNext)
                    Text(TapBehavior.followReadingDirection.localizedName)
                        .tag(TapBehavior.followReadingDirection)
                }
            }
        }
    }
}
