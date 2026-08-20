//
//  PluginInfoScreen.swift
//  mankai
//
//  Created by Travis XU on 26/6/2025.
//

import Combine
import SwiftUI
import WrappingHStack

struct PluginInfoScreen: View {
    @ObservedObject var plugin: Plugin

    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var errorTitle = ""

    @State private var showResetConfirmation = false
    @State private var showRemoveConfirmation = false

    @Environment(\.dismiss) private var dismiss

    private var supportedCapabilities: [PluginCapability] {
        PluginCapability.allCases.filter(plugin.supports)
    }

    var body: some View {
        Group {
            List {
                Section("info") {
                    HStack {
                        Text("id")
                        Spacer()
                        Text(plugin.id)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }

                    if let name = plugin.name {
                        LabeledContent("name") {
                            Text(name)
                        }
                    }

                    if let version = plugin.version {
                        LabeledContent("version") {
                            Text(version)
                        }
                    }

                    if let description = plugin.description {
                        LabeledContent("description") {
                            Text(description)
                        }
                    }

                    if !plugin.authors.isEmpty {
                        LabeledContent("authors") {
                            Text(plugin.authors.joined(separator: ", "))
                        }
                    }

                    if let repository = plugin.repository {
                        LabeledContent("repository") {
                            Text(repository)
                        }
                    }

                    if plugin.availableGenres.isEmpty {
                        LabeledContent("availableGenres") {
                            Text("noGenresAvailable")
                                .italic()
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("availableGenres")
                            WrappingHStack(plugin.availableGenres, id: \.self, lineSpacing: 8) {
                                genre in
                                Text(LocalizedStringKey(genre.rawValue))
                                    .genreTagStyle()
                            }
                        }
                    }

                    if supportedCapabilities.isEmpty {
                        LabeledContent("capabilities") {
                            Text("none")
                                .italic()
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("capabilities")
                            WrappingHStack(supportedCapabilities, id: \.self, lineSpacing: 8) {
                                capability in
                                Text(LocalizedStringKey(capability.rawValue))
                                    .genreTagStyle()
                            }
                        }
                    }
                }

                Section("sync") {
                    LabeledContent("syncAcrossDevices") {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(plugin.shouldSync ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(plugin.shouldSync ? "syncEnabled" : "syncDisabled")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if !plugin.configs.isEmpty {
                    Section("configs") {
                        ForEach(plugin.configs, id: \.key) { config in
                            switch config.type {
                            case .text:
                                TextConfigView(plugin: plugin, config: config)
                            case .password:
                                TextConfigView(plugin: plugin, config: config, isPassword: true)
                            case .number:
                                NumberConfigView(plugin: plugin, config: config)
                            case .boolean:
                                BooleanConfigView(plugin: plugin, config: config)
                            case .select:
                                SelectConfigView(plugin: plugin, config: config)
                            }
                        }
                    }
                }

                if !(plugin is AppDirPlugin) {
                    Section("actions") {
                        if !plugin.configs.isEmpty {
                            Button(
                                "resetConfigs",
                                role: .destructive,
                                action: {
                                    showResetConfirmation = true
                                }
                            )
                            .confirmationDialog(
                                "resetConfigs", isPresented: $showResetConfirmation,
                                titleVisibility: .visible
                            ) {
                                Button("reset", role: .destructive) {
                                    do {
                                        try plugin.resetConfigs()
                                    } catch {
                                        errorTitle = String(localized: "failedToResetConfigs")
                                        errorMessage = error.localizedDescription
                                        showErrorAlert = true
                                    }
                                }
                                Button("cancel", role: .cancel) {}
                            } message: {
                                Text("resetConfigsConfirmation")
                            }
                        }

                        Button(
                            "removePlugin",
                            role: .destructive,
                            action: {
                                showRemoveConfirmation = true
                            }
                        )
                        .confirmationDialog(
                            "removePlugin", isPresented: $showRemoveConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("remove", role: .destructive) {
                                do {
                                    try PluginService.shared.removePlugin(plugin.id)
                                    dismiss()
                                } catch {
                                    errorTitle = String(localized: "failedToRemovePlugin")
                                    errorMessage = error.localizedDescription
                                    showErrorAlert = true
                                }
                            }
                            Button("cancel", role: .cancel) {}
                        } message: {
                            Text("removePluginConfirmation")
                        }
                    }
                }
            }
        }
        .navigationTitle(plugin.name ?? plugin.id)
        .alert(errorTitle, isPresented: $showErrorAlert) {
            Button("ok") {}
        } message: {
            Text(errorMessage)
        }
    }
}

struct ConfigTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
            )
            .foregroundColor(.primary)
    }
}

struct TextConfigView: View {
    let plugin: Plugin
    let config: Config
    var isPassword: Bool = false

    @State private var textValue: String = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading) {
                Text(LocalizedStringKey(config.name))

                if let description = config.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Group {
                if isPassword {
                    SecureField(LocalizedStringKey(config.type.rawValue), text: $textValue)
                        .textContentType(.password)
                } else {
                    TextField(LocalizedStringKey(config.type.rawValue), text: $textValue)
                }
            }
            .textFieldStyle(ConfigTextFieldStyle())
            .autocapitalization(.none)
            .onAppear {
                updateTextValue()
            }
            .onReceive(plugin.objectWillChange) {
                updateTextValue()
            }
            .onChange(of: textValue, initial: false) { _, newValue in
                do {
                    try plugin.setConfig(key: config.key, value: newValue)
                } catch {
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
        .alert("failedToSetConfigValue", isPresented: $showErrorAlert) {
            Button("ok") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func updateTextValue() {
        let newValue =
            plugin.getConfig(config.key) as? String ?? config.defaultValue as? String ?? ""
        if textValue != newValue {
            textValue = newValue
        }
    }
}

struct NumberConfigView: View {
    let plugin: Plugin
    let config: Config

    @State private var numberValue: Double = 0
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading) {
                Text(LocalizedStringKey(config.name))

                if let description = config.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextField(
                LocalizedStringKey(config.type.rawValue), value: $numberValue, format: .number
            )
            .textFieldStyle(ConfigTextFieldStyle())
            .keyboardType(.decimalPad)
            .onAppear {
                updateNumberValue()
            }
            .onReceive(plugin.objectWillChange) {
                updateNumberValue()
            }
            .onChange(of: numberValue, initial: false) { _, newValue in
                do {
                    try plugin.setConfig(key: config.key, value: newValue)
                } catch {
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
        .alert("failedToSetConfigValue", isPresented: $showErrorAlert) {
            Button("ok") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func updateNumberValue() {
        var newValue: Double = 0
        if let value = plugin.getConfig(config.key) as? Double {
            newValue = value
        } else if let value = plugin.getConfig(config.key) as? Int {
            newValue = Double(value)
        } else if let value = config.defaultValue as? Double {
            newValue = value
        } else if let value = config.defaultValue as? Int {
            newValue = Double(value)
        }

        if numberValue != newValue {
            numberValue = newValue
        }
    }
}

struct BooleanConfigView: View {
    let plugin: Plugin
    let config: Config

    @State private var boolValue: Bool = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        Toggle(isOn: $boolValue) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(config.name))
                if let description = config.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            updateBoolValue()
        }
        .onReceive(plugin.objectWillChange) {
            updateBoolValue()
        }
        .onChange(of: boolValue, initial: false) { _, newValue in
            do {
                try plugin.setConfig(key: config.key, value: newValue)
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
        .alert("failedToSetConfigValue", isPresented: $showErrorAlert) {
            Button("ok") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func updateBoolValue() {
        let newValue =
            plugin.getConfig(config.key) as? Bool ?? config.defaultValue as? Bool ?? false
        if boolValue != newValue {
            boolValue = newValue
        }
    }
}

struct SelectConfigView: View {
    let plugin: Plugin
    let config: Config

    @State private var selectedValue: String? = nil
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    private var options: [String] {
        return config.options ?? []
    }

    var body: some View {
        Group {
            if selectedValue != nil {
                Picker(selection: $selectedValue) {
                    ForEach(options, id: \.self) { option in
                        Text(option)
                            .tag(option)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(config.name))
                        if let description = config.description {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedValue, initial: false) { _, newValue in
                    do {
                        if let newValue = newValue {
                            try plugin.setConfig(key: config.key, value: newValue)
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                        showErrorAlert = true
                    }
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .onAppear {
            updateSelectedValue()
        }
        .onReceive(plugin.objectWillChange) {
            updateSelectedValue()
        }
        .alert("failedToSetConfigValue", isPresented: $showErrorAlert) {
            Button("ok") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func updateSelectedValue() {
        var newValue =
            plugin.getConfig(config.key) as? String ?? config.defaultValue as? String ?? ""

        if !options.contains(newValue), !options.isEmpty {
            newValue = options.first ?? ""
        }

        if selectedValue != newValue {
            selectedValue = newValue
        }
    }
}
