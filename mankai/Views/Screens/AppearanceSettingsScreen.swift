//
//  AppearanceSettingsScreen.swift
//  mankai
//
//  Created by Travis XU on 31/8/2026.
//

import SwiftUI

struct AppearanceSettingsScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.accentColor.rawValue) private var accentColorRawValue: String =
        SettingsDefaults.accentColor.rawValue
    @State private var selectedIcon: AppIconOption = .sakura
    @State private var pendingIcon: AppIconOption?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                    ForEach(AppAccentColor.allCases) { accentColor in
                        Button {
                            accentColorRawValue = accentColor.rawValue
                        } label: {
                            ZStack {
                                Circle().fill(accentColor.color).frame(width: 40, height: 40)

                                if selectedAccentColor == accentColor {
                                    Image(systemName: "checkmark").fontWeight(.bold)
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("accentColor")
            } footer: {
                Text("accentColorDescription")
            }

            if UIApplication.shared.supportsAlternateIcons {
                Section {
                    ForEach(AppIconOption.allCases) { icon in
                        Button {
                            select(icon)
                        } label: {
                            HStack(spacing: 16) {
                                Image(icon.previewAssetName).resizable()
                                    .aspectRatio(contentMode: .fit).frame(width: 72, height: 72)
                                    .shadow(color: .black.opacity(0.12), radius: 3, y: 2)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(icon.localizedName).foregroundStyle(.primary)

                                    if icon == .sakura {
                                        Text("default").font(.caption).foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                if pendingIcon == icon {
                                    ProgressView()
                                } else if selectedIcon == icon {
                                    Image(systemName: "checkmark.circle.fill").font(.title2)
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("appIcon")
                } footer: {
                    Text("appIconDescription")
                }
            }
        }
        .navigationTitle("appearance").navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshSelection)
        .onChange(of: scenePhase) { _, newPhase in if newPhase == .active { refreshSelection() } }
        .alert(
            "appIconUpdateFailed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in if !isPresented { errorMessage = nil } })
        ) {
            Button("ok", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var selectedAccentColor: AppAccentColor {
        AppAccentColor(rawValue: accentColorRawValue) ?? SettingsDefaults.accentColor
    }

    private func select(_ icon: AppIconOption) {
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = String(localized: "appIconUnavailable")
            return
        }

        guard selectedIcon != icon else { return }

        pendingIcon = icon
        UIApplication.shared.setAlternateIconName(icon.alternateIconName) { error in
            DispatchQueue.main.async {
                pendingIcon = nil

                if let error {
                    Logger.ui.error("Failed to update app icon", error: error)
                    errorMessage = error.localizedDescription
                }

                refreshSelection()
            }
        }
    }

    private func refreshSelection() {
        selectedIcon = AppIconOption(alternateIconName: UIApplication.shared.alternateIconName)
    }
}

private enum AppIconOption: String, CaseIterable, Identifiable {
    case sakura
    case lily

    var id: Self { self }

    init(alternateIconName: String?) {
        switch alternateIconName { case nil: self = .sakura case "LilyIcon": self = .lily default:
            self = .sakura
        }
    }

    var alternateIconName: String? {
        switch self { case .sakura: nil case .lily: "LilyIcon"
        }
    }

    var previewAssetName: String {
        switch self { case .sakura: "SakuraIconPreview" case .lily: "LilyIconPreview"
        }
    }

    var localizedName: String {
        switch self { case .sakura: String(localized: "sakura") case .lily:
            String(localized: "lily")
        }
    }
}
