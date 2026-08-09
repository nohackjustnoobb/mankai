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
        var respectMangaReadingDirection: Bool =
            SettingsDefaults.respectMangaReadingDirection
    @AppStorage(SettingsKey.useSmartGrouping.rawValue) private var useSmartGrouping: Bool =
        SettingsDefaults.useSmartGrouping
    @AppStorage(SettingsKey.smartGroupingSensitivity.rawValue) private var smartGroupingSensitivity:
        Double =
            SettingsDefaults.smartGroupingSensitivity

    var body: some View {
        List {
            SettingsHeaderView(
                image: Image(systemName: "book.pages.fill"),
                color: .orange,
                title: String(localized: "reader"),
                description: String(localized: "readerDescription")
            )

            Section("imageGrouping") {
                Picker(
                    String(localized: "imageLayout"),
                    selection: Binding(
                        get: {
                            ImageLayout(rawValue: imageLayoutRawValue)
                                ?? SettingsDefaults.imageLayout
                        },
                        set: { imageLayoutRawValue = $0.rawValue }
                    )
                ) {
                    Text("auto").tag(ImageLayout.auto)
                    Text("onePerRow").tag(ImageLayout.onePerRow)
                    Text("twoPerRow").tag(ImageLayout.twoPerRow)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        String(localized: "useSmartGrouping"),
                        isOn: $useSmartGrouping
                    )
                    Text("useSmartGroupingDescription")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if useSmartGrouping {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("smartGroupingSensitivity")
                        Slider(
                            value: $smartGroupingSensitivity,
                            in: 0...1,
                            step: 0.1
                        )
                        Text("smartGroupingSensitivityDescription")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        String(localized: "respectMangaReadingDirection"),
                        isOn: $respectMangaReadingDirection
                    )
                    Text("respectMangaReadingDirectionDescription")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Picker(
                    String(localized: "readerType"),
                    selection: Binding(
                        get: {
                            ReaderType(rawValue: readerTypeRawValue) ?? SettingsDefaults.readerType
                        },
                        set: { readerTypeRawValue = $0.rawValue }
                    )
                ) {
                    Text("paged").tag(ReaderType.paged)
                    Text("continuous").tag(ReaderType.continuous)
                }
            }

            if let readerType = ReaderType(rawValue: readerTypeRawValue) {
                switch readerType {
                case .continuous:
                    ContinuousReaderSettingsView()
                case .paged:
                    PagedReaderSettingsView()
                }
            }
        }
        .navigationTitle("reader")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: useSmartGrouping) { _, isEnabled in
            guard !isEnabled else { return }

            Task {
                await AdjacencyModelWrapper.shared.unloadImmediately()
            }
        }
    }
}

struct ContinuousReaderSettingsView: View {
    @AppStorage(SettingsKey.CR_readingDirection.rawValue) private var readingDirectionRawValue:
        Int =
            SettingsDefaults.CR_readingDirection.rawValue
    @AppStorage(SettingsKey.CR_tapNavigation.rawValue) private var tapNavigation: Bool =
        SettingsDefaults.CR_tapNavigation
    @AppStorage(SettingsKey.CR_snapToPage.rawValue) private var snapToPage: Bool =
        SettingsDefaults.CR_snapToPage
    @AppStorage(SettingsKey.CR_softSnap.rawValue) private var softSnap: Bool =
        SettingsDefaults.CR_softSnap

    var body: some View {
        Section("continuousReaderSettings") {
            Picker(
                "readingDirection",
                selection: Binding(
                    get: {
                        ReadingDirection(rawValue: readingDirectionRawValue)
                            ?? SettingsDefaults.CR_readingDirection
                    },
                    set: { readingDirectionRawValue = $0.rawValue }
                )
            ) {
                Text("leftToRight").tag(ReadingDirection.leftToRight)
                Text("rightToLeft").tag(ReadingDirection.rightToLeft)
            }

            Toggle(
                String(localized: "tapNavigation"),
                isOn: $tapNavigation
            )

            Toggle(
                String(localized: "snapToPage"),
                isOn: $snapToPage
            )

            if snapToPage {
                Toggle(
                    String(localized: "softSnap"),
                    isOn: $softSnap
                )
            }
        }
    }
}

struct PagedReaderSettingsView: View {
    @AppStorage(SettingsKey.PR_readingDirection.rawValue) private var readingDirectionRawValue:
        Int =
            SettingsDefaults.PR_readingDirection.rawValue
    @AppStorage(SettingsKey.PR_navigationOrientation.rawValue) private
        var navigationOrientationRawValue: Int =
            SettingsDefaults.PR_navigationOrientation.rawValue
    @AppStorage(SettingsKey.PR_tapNavigation.rawValue) private var tapNavigation: Bool =
        SettingsDefaults.PR_tapNavigation
    @AppStorage(SettingsKey.PR_tapNavigationBehavior.rawValue) private
        var tapNavigationBehaviorRawValue: Int =
            SettingsDefaults.PR_tapNavigationBehavior.rawValue

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
                    },
                    set: { navigationOrientationRawValue = $0.rawValue }
                )
            ) {
                Text("horizontal").tag(NavigationOrientation.horizontal)
                Text("vertical").tag(NavigationOrientation.vertical)
            }

            Picker(
                "readingDirection",
                selection: Binding(
                    get: {
                        ReadingDirection(rawValue: readingDirectionRawValue)
                            ?? SettingsDefaults.PR_readingDirection
                    },
                    set: { readingDirectionRawValue = $0.rawValue }
                )
            ) {
                Text("leftToRight").tag(ReadingDirection.leftToRight)
                Text("rightToLeft").tag(ReadingDirection.rightToLeft)
            }

            Toggle(
                String(localized: "tapNavigation"),
                isOn: $tapNavigation
            )

            if tapNavigation && !isVertical {
                Picker(
                    "tapNavigationBehavior",
                    selection: Binding(
                        get: {
                            TapBehavior(rawValue: tapNavigationBehaviorRawValue)
                                ?? SettingsDefaults.PR_tapNavigationBehavior
                        },
                        set: { tapNavigationBehaviorRawValue = $0.rawValue }
                    )
                ) {
                    Text("previousNext").tag(TapBehavior.previousNext)
                    Text("followReadingDirection").tag(TapBehavior.followReadingDirection)
                }
            }
        }
    }
}
