//
//  AddImageProcessorModal.swift
//  mankai
//
//  Created by Travis XU on 26/9/2026.
//

import SwiftUI

struct AddImageProcessorModal: View {
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
