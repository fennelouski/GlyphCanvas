//
//  ArtworkDetailView.swift
//  GlyphCanvas
//

import SwiftUI

struct ArtworkDetailView: View {
    let artworkId: UUID

    @EnvironmentObject private var library: ArtworkLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var manifest: ArtworkManifest?
    @State private var loadError: String?
    @State private var showDeleteConfirm = false
    @State private var showExportSheet = false
    @State private var exportInFlight = false
    @State private var exportMessage: String?

    var body: some View {
        Group {
            if let err = loadError {
                ContentUnavailableView("Could not load", systemImage: "exclamationmark.triangle", description: Text(err))
            } else if let m = manifest {
                detailContent(manifest: m)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(manifest.map { GalleryArchiveNaming.displayTitle(titlePrefix: $0.titlePrefix, for: $0.id) } ?? "Artwork")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            do {
                manifest = try library.loadManifest(id: artworkId)
            } catch {
                loadError = error.localizedDescription
            }
        }
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete", role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
        .confirmationDialog("Delete this artwork?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteArtwork()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showExportSheet) {
            if let m = manifest {
                ArtworkExportSheet(
                    manifest: m,
                    isExporting: $exportInFlight,
                    onChoosePNG: { resolution in
                        await exportArtwork(manifest: m, resolution: resolution)
                    },
                    onChooseGIF: { config in
                        await exportGIF(manifest: m, config: config)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func detailContent(manifest: ArtworkManifest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                previewImage
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Created \(manifest.createdAt.formatted(date: .long, time: .shortened))")
                        .font(.subheadline)
                    Text("\(manifest.canvasWidth) × \(manifest.canvasHeight) px")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("\(manifest.operations.count) glyphs")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                NavigationLink(value: AppRoute.editorResume(artworkId)) {
                    Text("Continue editing")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showExportSheet = true
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                        .padding(10)
                }
                .buttonStyle(.bordered)

                if let msg = exportMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var previewImage: some View {
        let url = library.previewURL(for: artworkId)
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { ProgressView() }
            case .success(let image):
                image
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            case .failure:
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            @unknown default:
                EmptyView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func deleteArtwork() {
        do {
            try library.deleteArtwork(id: artworkId)
            dismiss()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func exportArtwork(manifest: ArtworkManifest, resolution: ArtworkExportResolution) async {
        let renderResult = await Task.detached {
            Result { try ArtworkExporter.renderImage(manifest: manifest, resolution: resolution) }
        }.value

        switch renderResult {
        case .success(let image):
            guard let data = ArtworkExporter.encodePNG(image) else {
                await MainActor.run {
                    exportMessage = "Could not encode PNG."
                    showExportSheet = false
                }
                return
            }
            let name = "GlyphCanvas-\(manifest.id.uuidString.prefix(8)).png"
            let saveResult = await PNGExportPlatform.save(data: data, suggestedFilename: name)
            await MainActor.run {
                switch saveResult {
                case .success(let message):
                    exportMessage = message
                case .failure(let error):
                    if error is PNGExportUserCancelled {
                        exportMessage = nil
                    } else {
                        exportMessage = "Save failed: \(error.localizedDescription)"
                    }
                }
                showExportSheet = false
            }
        case .failure(let error):
            await MainActor.run {
                exportMessage = "Export failed: \(error.localizedDescription)"
                showExportSheet = false
            }
        }
    }

    private func exportGIF(manifest: ArtworkManifest, config: GIFExportConfig) async {
        if let cachedURL = await GIFExportCache.shared.lookup(manifest: manifest, config: config),
           let data = try? Data(contentsOf: cachedURL)
        {
            let name = "GlyphCanvas-\(manifest.id.uuidString.prefix(8)).gif"
            let saveResult = await PNGExportPlatform.saveGIF(data: data, suggestedFilename: name)
            await MainActor.run {
                switch saveResult {
                case .success(let message):
                    exportMessage = message
                case .failure(let error):
                    if error is PNGExportUserCancelled {
                        exportMessage = nil
                    } else {
                        exportMessage = "Save failed: \(error.localizedDescription)"
                    }
                }
                showExportSheet = false
            }
            return
        }

        let framesResult: Result<[CGImage], Error> = await Task.detached {
            do {
                let frames = try await GIFExporter.renderFrames(manifest: manifest, config: config)
                return .success(frames)
            } catch {
                return .failure(error)
            }
        }.value

        switch framesResult {
        case .success(let frames):
            let encoded = await Task.detached {
                GIFExporter.encodeGIF(
                    frames: frames,
                    fps: config.fps,
                    transparent: config.transparentBackground,
                    capBytes: config.fileSizeCapBytes
                )
            }.value
            guard let data = encoded else {
                await MainActor.run {
                    exportMessage = "Could not encode GIF."
                    showExportSheet = false
                }
                return
            }
            do {
                _ = try await GIFExportCache.shared.store(data: data, manifest: manifest, config: config)
            } catch {
                await MainActor.run {
                    exportMessage = "Cache write failed: \(error.localizedDescription)"
                    showExportSheet = false
                }
                return
            }
            let name = "GlyphCanvas-\(manifest.id.uuidString.prefix(8)).gif"
            let saveResult = await PNGExportPlatform.saveGIF(data: data, suggestedFilename: name)
            await MainActor.run {
                switch saveResult {
                case .success(let message):
                    exportMessage = message
                case .failure(let error):
                    if error is PNGExportUserCancelled {
                        exportMessage = nil
                    } else {
                        exportMessage = "Save failed: \(error.localizedDescription)"
                    }
                }
                showExportSheet = false
            }
        case .failure(let error):
            await MainActor.run {
                exportMessage = "GIF render failed: \(error.localizedDescription)"
                showExportSheet = false
            }
        }
    }
}
