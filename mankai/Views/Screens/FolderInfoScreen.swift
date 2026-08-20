//
//  FolderInfoScreen.swift
//  mankai
//
//  Created by Travis XU on 20/8/2026.
//

import SwiftUI

struct FolderInfoScreen: View {
    let plugin: BrowsablePlugin
    private let editablePlugin: (any EditableFolderPlugin)?

    @ObservedObject private var browseService = BrowseService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var credentialsForm: FolderCredentials

    @State private var errorTitle: LocalizedStringKey = "failedToSaveFolder"
    @State private var errorMessage: String?
    @State private var showingRemoveConfirmation = false

    init(plugin: BrowsablePlugin) {
        self.plugin = plugin
        editablePlugin = plugin as? any EditableFolderPlugin

        _name = State(initialValue: editablePlugin?.pluginName ?? "")
        _credentialsForm = State(
            initialValue: editablePlugin?.credentials ?? FolderCredentials()
        )
    }

    private var isEditable: Bool {
        !(plugin is AppDirBrowsablePlugin)
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var folderTypeName: LocalizedStringKey {
        switch plugin {
        case is FsBrowsablePlugin:
            "fs"
        case is SmbBrowsablePlugin:
            "smb"
        case is WebDavBrowsablePlugin:
            "webdav"
        case is OpdsBrowsablePlugin:
            "opds"
        default:
            "folder"
        }
    }

    var body: some View {
        Form {
            Section("info") {
                LabeledContent("id") {
                    Text(plugin.id)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                LabeledContent("folderType") {
                    Text(folderTypeName)
                }

                LabeledContent("syncAcrossDevices") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(plugin.shouldSync ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(plugin.shouldSync ? "syncEnabled" : "syncDisabled")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if isEditable {
                Section {
                    TextField("default", text: $name)
                        .onChange(of: name, initial: false) {
                            saveSettings()
                        }
                } header: {
                    Text("displayName")
                }
            }

            switch plugin {
            case let filesystemPlugin as FsBrowsablePlugin:
                Section("filesystemSettings") {
                    LabeledContent("folder") {
                        Text(filesystemPlugin.url.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            case let smbPlugin as SmbBrowsablePlugin:
                Section("smbSettings") {
                    LabeledContent("server") {
                        Text(smbPlugin.host)
                    }

                    LabeledContent("port") {
                        Text(String(smbPlugin.port))
                    }

                    LabeledContent("share") {
                        Text(smbPlugin.share)
                    }

                    credentialFields
                }
            case let webDavPlugin as WebDavBrowsablePlugin:
                Section("webdavSettings") {
                    LabeledContent("serverUrl") {
                        Text(webDavPlugin.baseURL.absoluteString)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    credentialFields
                }
            case let opdsPlugin as OpdsBrowsablePlugin:
                Section("opdsSettings") {
                    LabeledContent("catalogUrl") {
                        Text(opdsPlugin.configuration.catalogURL.absoluteString)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    credentialFields
                }
            default:
                EmptyView()
            }

            if isEditable {
                Section("actions") {
                    Button("removeFolder", role: .destructive) {
                        showingRemoveConfirmation = true
                    }
                }
                .confirmationDialog(
                    "removeFolder",
                    isPresented: $showingRemoveConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("remove", role: .destructive) {
                        removeFolder()
                    }
                    Button("cancel", role: .cancel) {}
                } message: {
                    Text("removeFolderConfirmation")
                }
            }
        }
        .navigationTitle(name.isEmpty ? (plugin.name ?? plugin.id) : name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            browseService.objectWillChange.send()
        }
        .alert(errorTitle, isPresented: errorIsPresented) {
            Button("ok", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
    }

    @ViewBuilder
    private var credentialFields: some View {
        TextField("username", text: $credentialsForm.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.username)
            .onChange(of: credentialsForm.username, initial: false) {
                saveSettings()
            }

        SecureField("password", text: $credentialsForm.password)
            .textContentType(.password)
            .onChange(of: credentialsForm.password, initial: false) {
                saveSettings()
            }
    }

    private func saveSettings() {
        guard let editablePlugin else { return }

        do {
            editablePlugin.pluginName = Optional(name).trimmed
            if editablePlugin.credentials != nil {
                editablePlugin.credentials = credentialsForm
            }
            try editablePlugin.savePlugin()
        } catch {
            presentError(error)
        }
    }

    private func removeFolder() {
        do {
            try browseService.removePlugin(plugin.id)
            dismiss()
        } catch {
            presentError(error, title: "failedToRemovePlugin")
        }
    }

    private func presentError(
        _ error: Error,
        title: LocalizedStringKey = "failedToSaveFolder"
    ) {
        errorTitle = title
        errorMessage = error.localizedDescription
    }
}

// TODO: refactor this shit

private struct FolderCredentials {
    var username: String
    var password: String

    init(username: String? = nil, password: String? = nil) {
        self.username = username ?? ""
        self.password = password ?? ""
    }
}

private protocol EditableFolderPlugin: AnyObject {
    var pluginName: String? { get set }

    var credentials: FolderCredentials? { get set }

    func savePlugin() throws
}

extension FsBrowsablePlugin: EditableFolderPlugin {
    fileprivate var credentials: FolderCredentials? {
        get { nil }
        set {}
    }
}

private protocol FolderCredentialConfiguration {
    var username: String? { get set }
    var password: String? { get set }
}

extension SmbConnectionConfiguration: FolderCredentialConfiguration {}
extension WebDavConnectionConfiguration: FolderCredentialConfiguration {}
extension OpdsConnectionConfiguration: FolderCredentialConfiguration {}

private protocol AuthenticatedFolderPlugin: EditableFolderPlugin {
    associatedtype ConnectionConfiguration: FolderCredentialConfiguration

    var configuration: ConnectionConfiguration { get set }
}

extension AuthenticatedFolderPlugin {
    fileprivate var credentials: FolderCredentials? {
        get {
            FolderCredentials(
                username: configuration.username,
                password: configuration.password
            )
        }
        set {
            guard let newValue else { return }

            configuration.username = Optional(newValue.username).trimmed
            configuration.password = Optional(newValue.password).trimmed
        }
    }
}

extension SmbBrowsablePlugin: AuthenticatedFolderPlugin {}
extension WebDavBrowsablePlugin: AuthenticatedFolderPlugin {}
extension OpdsBrowsablePlugin: AuthenticatedFolderPlugin {}
