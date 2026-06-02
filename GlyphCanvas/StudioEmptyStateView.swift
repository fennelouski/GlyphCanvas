//
//  StudioEmptyStateView.swift
//  GlyphCanvas
//

import CoreGraphics
import SwiftUI

#if os(iOS)

/// iPhone empty Studio: hero, marketing copy, dashed import CTA, URL shortcut.
struct StudioEmptyStateView: View {
    let onImagePicked: (CGImage, ImportHints?) -> Void
    var autoPresentImagePicker: Binding<Bool>?

    @State private var showPasteURLSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                selectSourceSection
                heroSection
                headlineBlock
                bodyCopy
                secondaryActionsRow
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .font(.system(.body, design: .default))
        .sheet(isPresented: $showPasteURLSheet) {
            URLImportSheet(onImagePicked: { cg, hints in onImagePicked(cg, hints) })
        }
    }

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(GalleryTheme.cardSurface)
                .frame(height: 200)

            VStack(spacing: 16) {
                Image(systemName: "keyboard")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(GalleryTheme.studioAccent)

                HStack(spacing: 6) {
                    Circle()
                        .fill(GalleryTheme.studioAccent)
                        .frame(width: 6, height: 6)
                    Circle()
                        .fill(GalleryTheme.hudDetail.opacity(0.6))
                        .frame(width: 6, height: 6)
                    Circle()
                        .fill(GalleryTheme.hudDetail.opacity(0.6))
                        .frame(width: 6, height: 6)
                }

                photoStackDecoration
                    .padding(.bottom, 12)
            }
            .padding(.top, 28)
        }
        .frame(maxWidth: .infinity)
    }

    private var photoStackDecoration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .frame(width: 72, height: 48)
                .offset(x: 8, y: 6)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.18))
                .frame(width: 72, height: 48)
                .offset(x: -4, y: -2)
        }
        .frame(height: 56)
    }

    private var headlineBlock: some View {
        (Text("Ready for your first ")
            .foregroundStyle(GalleryTheme.headline)
        + Text("mechanical")
            .foregroundStyle(GalleryTheme.studioAccent)
        + Text(" masterpiece?")
            .foregroundStyle(GalleryTheme.headline))
        .font(.system(.title2, design: .default).weight(.bold))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var bodyCopy: some View {
        Text("Upload a photo to see it transformed into a unique typewriter-style mosaic. Every character is a brushstroke of digital ink.")
            .font(.system(.subheadline, design: .default))
            .foregroundStyle(GalleryTheme.bodyMuted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var selectSourceSection: some View {
        IOSOrVisionImageSourceMenu(
            onImagePicked: onImagePicked,
            autoPresentImagePicker: autoPresentImagePicker,
            usesBorderedProminentButtonStyle: false
        ) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(GalleryTheme.onAccentFill.opacity(0.95))
                        .frame(width: 56, height: 56)
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(GalleryTheme.studioAccent)
                        .symbolRenderingMode(.hierarchical)
                }
                Text("SELECT YOUR SOURCE")
                    .font(.system(.subheadline, design: .default).weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(GalleryTheme.studioAccent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .padding(.horizontal, 16)
            .overlay(
                DashedRoundedRectangle()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .foregroundStyle(GalleryTheme.studioStroke)
            )
        }
    }

    private var secondaryActionsRow: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                showPasteURLSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption.weight(.semibold))
                    Text("PASTE URL")
                        .font(.caption.weight(.heavy))
                        .tracking(0.4)
                }
                .foregroundStyle(GalleryTheme.headline)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

#endif
