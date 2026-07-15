//
//  GeneralSettingsScreen.swift
//  mankai
//
//  Created by Travis XU on 12/7/2025.
//

import SwiftUI

struct GeneralSettingsScreen: View {
    @AppStorage(SettingsKey.inMemoryCacheExpiryDuration.rawValue) private var inMemoryCacheExpiryDurationRawValue: Double = SettingsDefaults.inMemoryCacheExpiryDuration.rawValue
    @AppStorage(SettingsKey.diskCacheSizeLimit.rawValue) private var diskCacheSizeLimitRawValue: Int = SettingsDefaults.diskCacheSizeLimit.rawValue
    @AppStorage(SettingsKey.showDebugScreen.rawValue) private var showDebugScreen: Bool =
        SettingsDefaults.showDebugScreen
    @ObservedObject private var updateService = UpdateService.shared
    @State private var cacheSize: String = ""
    @State private var showClearCacheAlert = false

    var body: some View {
        List {
            Section {
                LabeledContent("lastUpdateTime") {
                    if let lastUpdateTime = updateService.lastUpdateTime {
                        Text(lastUpdateTime, style: .relative)
                            .foregroundColor(.secondary)
                    } else {
                        Text("never")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                Picker(
                    "inMemoryCacheExpiryDuration",
                    selection: Binding(
                        get: { CacheDuration(rawValue: inMemoryCacheExpiryDurationRawValue) ?? SettingsDefaults.inMemoryCacheExpiryDuration },
                        set: { inMemoryCacheExpiryDurationRawValue = $0.rawValue }
                    )
                ) {
                    Text("15m").tag(CacheDuration.fifteenMinutes)
                    Text("30m").tag(CacheDuration.thirtyMinutes)
                    Text("1h").tag(CacheDuration.oneHour)
                    Text("2h").tag(CacheDuration.twoHours)
                    Text("6h").tag(CacheDuration.sixHours)
                    Text("12h").tag(CacheDuration.twelveHours)
                    Text("1d").tag(CacheDuration.oneDay)
                }

                Picker(
                    "cacheSizeLimit",
                    selection: Binding(
                        get: { DiskCacheLimit(rawValue: diskCacheSizeLimitRawValue) ?? SettingsDefaults.diskCacheSizeLimit },
                        set: { diskCacheSizeLimitRawValue = $0.rawValue }
                    )
                ) {
                    Text("500mb").tag(DiskCacheLimit.fiveHundredMB)
                    Text("1gb").tag(DiskCacheLimit.oneGB)
                    Text("2gb").tag(DiskCacheLimit.twoGB)
                    Text("5gb").tag(DiskCacheLimit.fiveGB)
                    Text("10gb").tag(DiskCacheLimit.tenGB)
                }

                LabeledContent("cacheSize") {
                    Button(role: .destructive) {
                        showClearCacheAlert = true
                    } label: {
                        if cacheSize.isEmpty {
                            ProgressView()
                        } else {
                            HStack(spacing: 4) {
                                Text(cacheSize)
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
                .confirmationDialog(
                    "clearCache", isPresented: $showClearCacheAlert, titleVisibility: .visible
                ) {
                    Button("clear", role: .destructive) {
                        clearCache()
                    }
                    Button("cancel", role: .cancel) {}
                } message: {
                    Text("clearCacheMessage")
                }
            } header: {
                Text("cache")
            } footer: {
                Text("cacheDescription")
            }

            Section("about") {
                LabeledContent("version") {
                    Text(appVersion)
                }

                LabeledContent("license") {
                    Text("GNU GPLv3")
                }
            }

            Section {
                Toggle("showDebugScreen", isOn: $showDebugScreen)
            }
        }
        .navigationTitle("general")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            updateCacheSize()
        }
    }

    private var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        {
            return "\(version) (\(build))"
        } else if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        } else {
            return String(localized: "nil")
        }
    }

    private func updateCacheSize() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                return
            }

            var size: Int64 = 0
            if let enumerator = fileManager.enumerator(
                at: cacheDir, includingPropertiesForKeys: [.fileSizeKey]
            ) {
                for case let url as URL in enumerator {
                    if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
                       let fileSize = resourceValues.fileSize
                    {
                        size += Int64(fileSize)
                    }
                }
            }

            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useAll]
            formatter.countStyle = .file
            let formattedSize = formatter.string(fromByteCount: size)

            DispatchQueue.main.async {
                self.cacheSize = formattedSize
            }
        }
    }

    private func clearCache() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                return
            }

            do {
                let contents = try fileManager.contentsOfDirectory(
                    at: cacheDir, includingPropertiesForKeys: nil
                )
                for url in contents {
                    try fileManager.removeItem(at: url)
                }
            } catch {
                Logger.ui.error("Failed to clear cache: \(error)")
            }

            DispatchQueue.main.async {
                // Determine new size (should be small/zero)
                self.updateCacheSize()
            }
        }
    }
}
