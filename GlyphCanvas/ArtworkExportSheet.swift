//
//  ArtworkExportSheet.swift
//  GlyphCanvas
//

import SwiftUI

struct ArtworkExportSheet: View {
    let manifest: ArtworkManifest
    @Binding var isExporting: Bool
    /// Called when user picks a preset; caller runs render/save and clears `isExporting`.
    let onChoose: (ArtworkExportResolution) async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    Section {
                        Text("Source: \(manifest.canvasWidth) × \(manifest.canvasHeight) px")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Section("Resolution") {
                        ForEach(ArtworkExportResolution.allCases, id: \.self) { preset in
                            Button {
                                Task {
                                    isExporting = true
                                    await onChoose(preset)
                                    isExporting = false
                                }
                            } label: {
                                HStack {
                                    Text(rowTitle(for: preset))
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "square.and.arrow.down")
                                        .foregroundStyle(.secondary)
                                        .opacity(isExporting ? 0.35 : 1)
                                }
                            }
                            .disabled(isExporting)
                        }
                    }
                }

                if isExporting {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                    ProgressView("Exporting…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .navigationTitle("Export")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isExporting)
                }
            }
        }
    }

    private func rowTitle(for preset: ArtworkExportResolution) -> String {
        let (w, h) = preset.targetSize(for: manifest)
        return "\(preset.presetTitle) — \(w) × \(h) px"
    }
}

#if DEBUG
#Preview {
    ArtworkExportSheet(
        manifest: ArtworkManifest(
            canvasWidth: 512,
            canvasHeight: 512,
            operations: []
        ),
        isExporting: .constant(false),
        onChoose: { _ in }
    )
}
#endif
