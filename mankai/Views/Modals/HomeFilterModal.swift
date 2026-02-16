//
//  HomeFilterModal.swift
//  mankai
//
//  Created by Travis XU on 16/2/2026.
//

import SwiftUI

struct HomeFilterModal: View {
    @Binding var isPresented: Bool
    @Binding var showPlugins: [String]
    let availablePlugins: [Plugin]
    let onReset: () -> Void
    let onApply: () -> Void

    @State private var tempShowPlugins: [String]

    init(
        isPresented: Binding<Bool>,
        showPlugins: Binding<[String]>,
        availablePlugins: [Plugin],
        onReset: @escaping () -> Void,
        onApply: @escaping () -> Void
    ) {
        _isPresented = isPresented
        _showPlugins = showPlugins
        self.availablePlugins = availablePlugins
        self.onReset = onReset
        self.onApply = onApply
        _tempShowPlugins = State(initialValue: showPlugins.wrappedValue)
    }

    var body: some View {
        NavigationView {
            List {
                Section("showPlugins") {
                    ForEach(availablePlugins, id: \.id) { plugin in
                        Button(action: {
                            if tempShowPlugins.contains(plugin.id) {
                                tempShowPlugins.removeAll { $0 == plugin.id }
                            } else {
                                tempShowPlugins.append(plugin.id)
                            }
                        }) {
                            HStack {
                                Text(plugin.name ?? plugin.id)
                                    .foregroundColor(.primary)
                                Spacer()
                                if tempShowPlugins.contains(plugin.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Section {
                    Button(
                        "reset",
                        role: .destructive,
                        action: {
                            onReset()
                            isPresented = false
                        }
                    )
                }
            }
            .navigationTitle("filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        isPresented = false
                    }) {
                        Text("cancel")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        showPlugins = tempShowPlugins
                        onApply()
                        isPresented = false
                    }) {
                        Text("done")
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            tempShowPlugins = showPlugins
        }
    }
}
