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
        .navigationTitle("Artwork")
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

                if let url = previewFileURL {
                    ShareLink(item: url) {
                        Label("Share image", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(10)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }

    private var previewFileURL: URL? {
        let url = library.previewURL(for: artworkId)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
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
}
