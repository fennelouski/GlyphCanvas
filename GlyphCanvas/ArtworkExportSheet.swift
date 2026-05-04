//
//  ArtworkExportSheet.swift
//  GlyphCanvas
//

import SwiftUI

private enum ExportFormatTab: String, CaseIterable, Identifiable, Hashable {
    case png
    case gif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png: return "PNG"
        case .gif: return "GIF"
        }
    }
}

struct ArtworkExportSheet: View {
    let manifest: ArtworkManifest
    @Binding var isExporting: Bool
    let onChoosePNG: (ArtworkExportResolution) async -> Void
    let onChooseGIF: (GIFExportConfig) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tab: ExportFormatTab = .png
    @State private var gifConfig = GIFExportConfig.default()

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    Picker("Format", selection: $tab) {
                        ForEach(ExportFormatTab.allCases) { t in
                            Text(t.title).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    Group {
                        switch tab {
                        case .png:
                            pngList
                        case .gif:
                            GIFExportPanel(manifest: manifest, config: $gifConfig)
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
                if tab == .gif {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Export GIF") {
                            Task {
                                isExporting = true
                                await onChooseGIF(gifConfig)
                                isExporting = false
                            }
                        }
                        .disabled(isExporting)
                    }
                }
            }
        }
    }

    private var pngList: some View {
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
                            await onChoosePNG(preset)
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
        onChoosePNG: { _ in },
        onChooseGIF: { _ in }
    )
}
#endif
