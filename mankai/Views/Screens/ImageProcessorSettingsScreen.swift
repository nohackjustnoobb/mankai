import SwiftUI

struct ImageProcessorSettingsScreen: View {
    @ObservedObject private var service = ImageProcessingService.shared
    @State private var showingAdd = false
    @State private var showingDeleteConfirmation = false
    @State private var processorIdsToRemove: [String] = []

    var body: some View {
        List {
            if service.processors.isEmpty {
                ContentUnavailableView(
                    "imageProcessorEmptyTitle", systemImage: "photo.on.rectangle.angled",
                    description: Text("imageProcessorEmptyDescription"))
            } else {
                Section {
                    ForEach(service.processors, id: \.id) { model in
                        HStack {
                            NavigationLink {
                                ImageProcessorConfigurationScreen(id: model.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.titleKey)
                                    Text(model.descriptionKey).font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Toggle(
                                isOn: Binding(
                                    get: {
                                        service.processors.first(where: { $0.id == model.id })?
                                            .isEnabled ?? false
                                    }, set: { service.setEnabled($0, for: model.id) })
                            ) { Text(model.titleKey) }
                            .labelsHidden()
                        }
                    }
                    .onMove { source, destination in
                        var ids = service.processors.map(\.id)
                        ids.move(fromOffsets: source, toOffset: destination)
                        service.setOrder(ids)
                    }
                    .onDelete { offsets in
                        processorIdsToRemove = offsets.map { service.processors[$0].id }
                        showingDeleteConfirmation = true
                    }
                } header: {
                    Text("imageProcessing")
                } footer: {
                    Text("imageProcessorOrderHint")
                }
            }
        }
        .navigationTitle("imageProcessing").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !service.processors.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) { AddImageProcessorModal() }
        .confirmationDialog(
            "remove", isPresented: $showingDeleteConfirmation, titleVisibility: .visible
        ) {
            Button("remove", role: .destructive) {
                service.remove(ids: processorIdsToRemove)
                processorIdsToRemove = []
            }
            Button("cancel", role: .cancel) { processorIdsToRemove = [] }
        } message: {
            Text("removeImageProcessorsConfirmation")
        }
        .alert(
            "error",
            isPresented: Binding(
                get: { service.errorMessage != nil }, set: { if !$0 { service.errorMessage = nil } }
            )
        ) {
            Button("ok", role: .cancel) { service.errorMessage = nil }
        } message: {
            Text(service.errorMessage ?? "")
        }
    }
}

private struct AddImageProcessorModal: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = ImageProcessingService.shared

    var body: some View {
        NavigationStack {
            List {
                Button {
                    if service.add(UpscalingImageProcessor.defaultProcessor) { dismiss() }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(UpscalingImageProcessor.titleKey)
                        Text(UpscalingImageProcessor.descriptionKey).font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Button {
                    if service.add(DownsampleImageProcessor.defaultProcessor) { dismiss() }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(DownsampleImageProcessor.titleKey)
                        Text(DownsampleImageProcessor.descriptionKey).font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain).navigationTitle("addImageProcessor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("cancel") { dismiss() } }
            }
            .alert(
                "error",
                isPresented: Binding(
                    get: { service.errorMessage != nil },
                    set: { if !$0 { service.errorMessage = nil } })
            ) {
                Button("ok", role: .cancel) { service.errorMessage = nil }
            } message: {
                Text(service.errorMessage ?? "")
            }
        }
    }
}

private struct ImageProcessorConfigurationScreen: View {
    let id: String
    @ObservedObject private var service = ImageProcessingService.shared

    private var model: ImageProcessorInstance? { service.processors.first(where: { $0.id == id }) }

    var body: some View {
        Form {
            if let model {
                Section {
                    Toggle(
                        "imageProcessorEnabled",
                        isOn: Binding(
                            get: {
                                service.processors.first(where: { $0.id == id })?.isEnabled ?? false
                            }, set: { service.setEnabled($0, for: id) }))
                }

                if model.type == UpscalingImageProcessor.type,
                    let processor = service.processor(id: id, as: UpscalingImageProcessor.self)
                {
                    Section("imageUpscaling") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("upscaleSensitivity")
                                Spacer()
                                Text(processor.sensitivityLabel).foregroundStyle(.secondary)
                            }
                            Slider(
                                value: Binding(
                                    get: {
                                        service.processor(id: id, as: UpscalingImageProcessor.self)?
                                            .threshold ?? processor.threshold
                                    },
                                    set: {
                                        service.update(
                                            id: id,
                                            processor: UpscalingImageProcessor(
                                                context: processor.context, threshold: $0))
                                    }), in: 0.5...2.5, step: 0.5)
                            Text("upscaleSensitivityDescription").font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if model.type == DownsampleImageProcessor.type,
                    let processor = service.processor(id: id, as: DownsampleImageProcessor.self)
                {
                    Section("downsampleImages") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("downsampleMemorySavings")
                                Spacer()
                                Text(processor.memorySavingsLabel).foregroundStyle(.secondary)
                            }
                            Slider(
                                value: Binding(
                                    get: {
                                        service.processor(
                                            id: id, as: DownsampleImageProcessor.self)?
                                            .aggressiveness ?? processor.aggressiveness
                                    },
                                    set: {
                                        service.update(
                                            id: id,
                                            processor: DownsampleImageProcessor(aggressiveness: $0))
                                    }), in: 0...1, step: 0.5)
                            Text("downsampleMemorySavingsDescription").font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("imageProcessorNoSettings").foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("imageProcessorRemoved", systemImage: "slider.horizontal.3")
            }
        }
        .navigationTitle(Text(model?.titleKey ?? "imageProcessing"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "error",
            isPresented: Binding(
                get: { service.errorMessage != nil }, set: { if !$0 { service.errorMessage = nil } }
            )
        ) {
            Button("ok", role: .cancel) { service.errorMessage = nil }
        } message: {
            Text(service.errorMessage ?? "")
        }
    }
}
