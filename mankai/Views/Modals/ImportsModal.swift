//
//  ImportsModal.swift
//  mankai
//
//  Created by Travis XU on 15/7/2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct ImportsModal: View {
    @ObservedObject private var browseService = BrowseService.shared
    @Environment(\.dismiss) private var dismiss

    var onImport: ((ImportableBrowsablePlugin) -> Void)?
    var initialFiles: [URL]

    @State private var selectedFiles: [URL]
    @State private var selectedPluginId: String = AppDirBrowsablePlugin.shared.id
    @State private var showingFileImporter = false
    @State private var isImporting = false
    @State private var importError: String?
    @State private var showingError = false

    init(
        initialFiles: [URL] = [],
        onImport: ((ImportableBrowsablePlugin) -> Void)? = nil
    ) {
        self.initialFiles = initialFiles
        self.onImport = onImport
        _selectedFiles = State(initialValue: initialFiles)
    }

    private var supportedContentTypes: [UTType] {
        (selectedPlugin?.supportedExtensions ?? AppDirBrowsablePlugin.shared.supportedExtensions)
            .compactMap { ext in
                if ext == "epub" {
                    return .epub
                }

                return UTType(filenameExtension: ext)
            }
    }

    private var selectedPlugin: ImportableBrowsablePlugin? {
        browseService.getImportablePlugin(selectedPluginId)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingFileImporter = true
                    } label: {
                        HStack {
                            Text("selectFiles")
                            Spacer()
                            if selectedFiles.isEmpty {
                                Text("none")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(
                                    String(
                                        format: String(localized: "fileCountFormat"),
                                        selectedFiles.count
                                    )
                                )
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    if !selectedFiles.isEmpty {
                        Text(selectedFiles.map(\.lastPathComponent).joined(separator: ", "))
                            .lineLimit(2)
                    }
                }

                Section("importTo") {
                    Picker("folder", selection: $selectedPluginId) {
                        ForEach(browseService.importablePlugins, id: \.id) { plugin in
                            Text(plugin.name ?? plugin.id)
                                .tag(plugin.id)
                        }
                    }
                }
            }
            .navigationTitle("imports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("import") {
                        Task {
                            await importFiles()
                        }
                    }
                    .disabled(selectedFiles.isEmpty || selectedPlugin == nil || isImporting)
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: supportedContentTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    selectedFiles = urls
                case .failure(let error):
                    importError = error.localizedDescription
                    showingError = true
                }
            }
            .alert("failedToImport", isPresented: $showingError) {
                Button("ok", role: .cancel) {}
            } message: {
                if let importError {
                    Text(importError)
                }
            }
        }
    }

    private func importFiles() async {
        guard let plugin = selectedPlugin else { return }

        isImporting = true
        defer { isImporting = false }

        do {
            for file in selectedFiles {
                try await plugin.importFile(from: file)
            }
            onImport?(plugin)
            dismiss()
        } catch {
            importError = error.localizedDescription
            showingError = true
        }
    }
}
