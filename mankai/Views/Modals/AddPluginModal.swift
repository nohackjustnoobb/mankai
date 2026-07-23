//
//  AddPluginModal.swift
//  mankai
//
//  Created by Travis XU on 22/6/2025.
//

import SwiftUI

struct AddPluginModal: View {
    @Environment(\.dismiss) var dismiss

    enum PluginType: String, CaseIterable, Identifiable {
        case jsPlugin
        case fsPlugin
        case httpPlugin

        var id: String {
            rawValue
        }
    }

    @State private var selectedPluginType: PluginType = .jsPlugin
    @State private var useJson = false
    @State private var jsonInput: String = ""
    @State private var urlInput: String = ""

    // FsPlugin States
    @State private var selectedFolder: URL?
    @State private var isReadOnly: Bool = false
    @State private var showFileImporter: Bool = false

    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isProcessing: Bool = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    Picker("pluginType", selection: $selectedPluginType) {
                        ForEach(PluginType.allCases) { type in
                            Text(LocalizedStringKey(type.rawValue)).tag(type)
                        }
                    }
                }

                if selectedPluginType == .jsPlugin {
                    Section {
                        Toggle(isOn: $useJson) {
                            Text("useJson")
                        }
                        if useJson {
                            TextField("json", text: $jsonInput)
                                .textInputAutocapitalization(.never)
                        } else {
                            TextField("url", text: $urlInput)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                        }
                    } header: {
                        Text("jsPluginSettings")
                    }
                } else if selectedPluginType == .fsPlugin {
                    Section {
                        Button(action: {
                            showFileImporter = true
                        }) {
                            HStack {
                                Text("selectFolder")
                                Spacer()
                                if let selectedFolder = selectedFolder {
                                    Text(selectedFolder.lastPathComponent)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("none")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Toggle("readOnly", isOn: $isReadOnly)
                    } header: {
                        Text("fsPluginSettings")
                    }
                } else if selectedPluginType == .httpPlugin {
                    Section {
                        TextField("url", text: $urlInput)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                    } header: {
                        Text("httpPluginSettings")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("addPlugin")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("cancel")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        action: {
                            Task {
                                isProcessing = true
                                defer { isProcessing = false }

                                switch selectedPluginType {
                                case .jsPlugin:
                                    let plugin: JsPlugin?

                                    if useJson {
                                        plugin = parsePluginFromJson(jsonInput)
                                    } else {
                                        plugin = await parsePluginFromUrl(urlInput)
                                    }

                                    guard let plugin = plugin else {
                                        errorMessage = String(localized: "failedToParsePlugin")
                                        showError = true
                                        return
                                    }

                                    do {
                                        try PluginService.shared.addPlugin(plugin)
                                        dismiss()
                                    } catch {
                                        errorMessage = error.localizedDescription
                                        showError = true
                                    }
                                case .fsPlugin:
                                    guard let selectedFolder = selectedFolder else {
                                        errorMessage = String(localized: "noFolderSelected")
                                        showError = true
                                        return
                                    }

                                    // Check if the folder is accessible
                                    guard selectedFolder.startAccessingSecurityScopedResource() else {
                                        errorMessage = String(localized: "failedToAccessFolder")
                                        showError = true
                                        return
                                    }
                                    defer { selectedFolder.stopAccessingSecurityScopedResource() }

                                    let plugin: ReadFsPlugin
                                    do {
                                        if isReadOnly {
                                            plugin = try ReadFsPlugin(url: selectedFolder)
                                        } else {
                                            plugin = try ReadWriteFsPlugin(url: selectedFolder)
                                        }

                                        try PluginService.shared.addPlugin(plugin)
                                        dismiss()
                                    } catch {
                                        errorMessage = error.localizedDescription
                                        showError = true
                                    }
                                case .httpPlugin:
                                    guard let plugin = await parseHttpPluginFromUrl(urlInput) else {
                                        errorMessage = String(localized: "failedToParsePlugin")
                                        showError = true
                                        return
                                    }

                                    do {
                                        try PluginService.shared.addPlugin(plugin)
                                        dismiss()
                                    } catch {
                                        errorMessage = error.localizedDescription
                                        showError = true
                                    }
                                }
                            }
                        }
                    ) {
                        if isProcessing {
                            ProgressView()
                        } else {
                            Text("add")
                        }
                    }
                    .disabled(
                        isProcessing
                            || (selectedPluginType == .jsPlugin
                                && (useJson ? jsonInput.isEmpty : urlInput.isEmpty))
                            || (selectedPluginType == .fsPlugin && selectedFolder == nil)
                            || (selectedPluginType == .httpPlugin && urlInput.isEmpty)
                    )
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    if let url = urls.first {
                        selectedFolder = url
                    }
                case let .failure(error):
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
            .alert("failedToAddPlugin", isPresented: $showError) {
                Button("ok", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
}

private func parsePluginFromJson(_ input: String) -> JsPlugin? {
    guard let data = input.data(using: .utf8) else {
        return nil
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }

    return JsPlugin.fromJson(json)
}

private func parsePluginFromUrl(_ urlString: String) async -> JsPlugin? {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed) else {
        return nil
    }

    return await JsPlugin.fromUrl(url)
}

private func parseHttpPluginFromUrl(_ urlString: String) async -> HttpPlugin? {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed) else {
        return nil
    }

    return await HttpPlugin.fromUrl(url)
}
