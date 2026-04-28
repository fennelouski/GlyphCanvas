//
//  GalleryPlaybackFullscreenView.swift
//  GlyphCanvas
//

import SwiftUI

struct GalleryPlaybackFullscreenView: View {
    let artworkID: UUID
    @Binding var isPresented: Bool

    @EnvironmentObject private var library: ArtworkLibrary
    @StateObject private var viewModel = AppViewModel()

    @State private var showPauseOverlay = false

    private let swipeDismissThreshold: CGFloat = 100

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            if let image = viewModel.displayImage {
                StudioMosaicInteractiveCanvas(
                    displayImage: image,
                    sourceOverlay: viewModel.sourceImageForOverlay,
                    showSourceOverlay: viewModel.showSourceOverlay,
                    imagePadding: 10,
                    onRequestFullscreen: nil,
                    scrollDisabledBinding: nil
                )
            } else {
                ProgressView()
                    .tint(GalleryTheme.accent)
            }

            if viewModel.isPlayingBack, !showPauseOverlay {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.pauseGalleryLoopPlayback()
                        showPauseOverlay = true
                    }
            }

            if showPauseOverlay {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white.opacity(0.95))
                        }
                        .buttonStyle(.plain)
                        .padding(16)
                    }
                    Spacer()
                    Button {
                        resumePlayback()
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 72))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    HStack {
                        favoriteButton
                            .padding(24)
                        Spacer()
                    }
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let h = value.translation.height
                    let w = abs(value.translation.width)
                    if h > swipeDismissThreshold, h > w {
                        dismiss()
                    }
                }
        )
        .task(id: artworkID) {
            viewModel.galleryLibrary = library
            await viewModel.restoreArtwork(id: artworkID, library: library)
            let n = max(1, viewModel.glyphHistory.count)
            viewModel.playbackGlyphsPerSecond = Double(n) / 6.0
            viewModel.startLoopingPlayback(library: library)
        }
        .onDisappear {
            viewModel.endGalleryLoopPlaybackSession()
        }
        #if os(macOS)
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        #endif
    }

    private var favoriteButton: some View {
        let favorited = library.entries.first(where: { $0.id == artworkID })?.isFavorite == true
        return Button {
            try? library.toggleFavorite(id: artworkID)
        } label: {
            Image(systemName: favorited ? "heart.fill" : "heart")
                .font(.title2.weight(.semibold))
                .foregroundStyle(favorited ? GalleryTheme.accent : .white.opacity(0.9))
        }
        .buttonStyle(.plain)
    }

    private func resumePlayback() {
        showPauseOverlay = false
        viewModel.resumeGalleryLoopPlayback(library: library)
    }

    private func dismiss() {
        viewModel.endGalleryLoopPlaybackSession()
        isPresented = false
    }
}
