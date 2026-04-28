//
//  GalleryView.swift
//  GlyphCanvas
//

import CoreGraphics
import SwiftUI

struct GalleryView: View {
    @EnvironmentObject private var library: ArtworkLibrary
    @EnvironmentObject private var navigationHistory: MacNavigationHistory
    @StateObject private var holdPreviewPlayer = GalleryHoldPreviewPlayer()
    @Binding var mainTab: MainTab
    @Binding var studioAutoPresentImagePicker: Bool

    @State private var holdSessionID = UUID()
    @State private var pressingEntryID: UUID?
    @State private var activePreviewEntryID: UUID?
    @State private var pressStartedAt: Date?
    @State private var fullscreenItem: GalleryFullscreenItem?

    var body: some View {
        Group {
            if library.entries.isEmpty {
                LandingEmptyStateView(
                    mainTab: $mainTab,
                    studioAutoPresentImagePicker: $studioAutoPresentImagePicker
                )
            } else {
                GeometryReader { geo in
                    collectedGallery(geo: geo)
                }
            }
        }
        .background(library.entries.isEmpty ? GalleryTheme.background : GalleryTheme.galleryScreenBackground)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #else
        .navigationTitle("")
        #endif
        .refreshable {
            try? library.reloadFromDisk()
        }
        #if os(iOS)
        .fullScreenCover(item: $fullscreenItem) { item in
            GalleryPlaybackFullscreenView(
                artworkID: item.id,
                isPresented: Binding(
                    get: { fullscreenItem != nil },
                    set: { if !$0 { fullscreenItem = nil } }
                )
            )
            .environmentObject(library)
        }
        #else
        .sheet(item: $fullscreenItem) { item in
            GalleryPlaybackFullscreenView(
                artworkID: item.id,
                isPresented: Binding(
                    get: { fullscreenItem != nil },
                    set: { if !$0 { fullscreenItem = nil } }
                )
            )
            .environmentObject(library)
            .frame(minWidth: 720, minHeight: 560)
        }
        #endif
    }

    // MARK: - Collected works (masonry)

    private func collectedGallery(geo: GeometryProxy) -> some View {
        let horizontalPadding: CGFloat = 16
        let spacing: CGFloat = 12
        let columnCount = Self.columnCount(forWidth: geo.size.width)
        let gutter = spacing * CGFloat(max(0, columnCount - 1))
        let columnWidth = max(
            72,
            (geo.size.width - horizontalPadding * 2 - gutter) / CGFloat(columnCount)
        )
        let columns = Self.splitIntoMasonryColumns(
            library.entries,
            columnCount: columnCount,
            columnWidth: columnWidth,
            spacing: spacing
        )

        return ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GalleryCollectedTopBar()
                    GalleryArchiveHeader()

                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(0..<columnCount, id: \.self) { index in
                            VStack(spacing: spacing) {
                                ForEach(columns[index]) { entry in
                                    GalleryEntryTile(
                                        entry: entry,
                                        columnWidth: columnWidth,
                                        holdPreviewPlayer: holdPreviewPlayer,
                                        holdSessionID: $holdSessionID,
                                        pressingEntryID: $pressingEntryID,
                                        activePreviewEntryID: $activePreviewEntryID,
                                        pressStartedAt: $pressStartedAt,
                                        fullscreenItem: $fullscreenItem
                                    )
                                }
                            }
                            .frame(width: columnWidth)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    GalleryNewArchivePlaceholder {
                        studioAutoPresentImagePicker = true
                        mainTab = .studio
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 96)
            }

            Button {
                studioAutoPresentImagePicker = true
                mainTab = .studio
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(GalleryTheme.onAccentFill)
                    .frame(width: 56, height: 56)
                    .background(GalleryTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create new artwork")
            .padding(.trailing, 18)
            .padding(.bottom, 6)
        }
    }

    /// 2 columns on phones / narrow; 3 on regular width (e.g. iPad, macOS).
    private static func columnCount(forWidth width: CGFloat) -> Int {
        if width >= 900 { return 3 }
        return 2
    }

    /// Shortest-column assignment using estimated card height (image + metadata chrome).
    private static func splitIntoMasonryColumns(
        _ items: [ArtworkIndexEntry],
        columnCount: Int,
        columnWidth: CGFloat,
        spacing: CGFloat
    ) -> [[ArtworkIndexEntry]] {
        guard columnCount > 0 else { return [items] }
        var columns = Array(repeating: [ArtworkIndexEntry](), count: columnCount)
        var heights = Array(repeating: CGFloat(0), count: columnCount)

        for item in items {
            let est = estimatedCardHeight(entry: item, columnWidth: columnWidth)
            guard let shortest = heights.indices.min(by: { heights[$0] < heights[$1] }) else { continue }
            columns[shortest].append(item)
            heights[shortest] += est + spacing
        }
        return columns
    }

    /// Matches `GalleryMasonryCard` layout: image height + footer block.
    private static func estimatedCardHeight(entry: ArtworkIndexEntry, columnWidth: CGFloat) -> CGFloat {
        let aspect = CGFloat(entry.canvasWidth) / CGFloat(max(1, entry.canvasHeight))
        let imageHeight = columnWidth / max(0.01, aspect)
        return imageHeight + cardFooterChrome
    }

    private static let cardFooterChrome: CGFloat = 86
}

private struct GalleryFullscreenItem: Identifiable {
    let id: UUID
}

private struct GalleryEntryTile: View {
    let entry: ArtworkIndexEntry
    let columnWidth: CGFloat

    @EnvironmentObject private var library: ArtworkLibrary
    @EnvironmentObject private var navigationHistory: MacNavigationHistory

    @ObservedObject var holdPreviewPlayer: GalleryHoldPreviewPlayer
    @Binding var holdSessionID: UUID
    @Binding var pressingEntryID: UUID?
    @Binding var activePreviewEntryID: UUID?
    @Binding var pressStartedAt: Date?
    @Binding var fullscreenItem: GalleryFullscreenItem?

    private let longPressLeadNanoseconds: UInt64 = 400_000_000
    private let fullscreenHoldNanoseconds: UInt64 = 12_000_000_000
    private let tapNavigationMaxSeconds: TimeInterval = 0.25

    var body: some View {
        GalleryMasonryCard(
            entry: entry,
            columnWidth: columnWidth,
            previewImage: activePreviewEntryID == entry.id ? holdPreviewPlayer.currentImage : nil
        )
        .overlay {
            GalleryTilePressOverlay(
                onPressBegan: { tilePressBegan() },
                onPressReleased: { duration, liftedNormally in
                    tilePressReleased(duration: duration, liftedNormally: liftedNormally)
                }
            )
        }
    }

    private func tilePressBegan() {
        guard pressingEntryID == nil else { return }
        pressingEntryID = entry.id
        holdSessionID = UUID()
        let session = holdSessionID
        pressStartedAt = Date()
        Task {
            try? await Task.sleep(nanoseconds: longPressLeadNanoseconds)
            await MainActor.run {
                guard session == holdSessionID, pressingEntryID == entry.id else { return }
                holdPreviewPlayer.begin(library: library, artworkID: entry.id)
                activePreviewEntryID = entry.id
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: fullscreenHoldNanoseconds)
            await MainActor.run {
                guard session == holdSessionID, pressingEntryID == entry.id else { return }
                fullscreenItem = GalleryFullscreenItem(id: entry.id)
                holdPreviewPlayer.cancel()
                activePreviewEntryID = nil
                pressingEntryID = nil
                holdSessionID = UUID()
            }
        }
    }

    private func tilePressReleased(duration: TimeInterval, liftedNormally: Bool) {
        let eid = entry.id
        if liftedNormally, duration < tapNavigationMaxSeconds {
            navigationHistory.galleryPath.append(.detail(eid))
        }
        holdSessionID = UUID()
        if activePreviewEntryID == eid {
            holdPreviewPlayer.cancel()
            activePreviewEntryID = nil
        }
        pressingEntryID = nil
        pressStartedAt = nil
    }
}

// MARK: - Collected header & placeholder

private struct GalleryCollectedTopBar: View {
    var body: some View {
        HStack {
            Image(systemName: "square.grid.2x2")
                .font(.body.weight(.semibold))
                .foregroundStyle(GalleryTheme.accent)
                .frame(width: 44, height: 40, alignment: .leading)
                .accessibilityHidden(true)

            Spacer(minLength: 0)

            Text("GALLERY")
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(GalleryTheme.accent)
                .tracking(0.8)

            Spacer(minLength: 0)

            Menu {
                Button("About GlyphCanvas") {}
            } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(GalleryTheme.accent)
                    .frame(width: 44, height: 40, alignment: .trailing)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
    }
}

private struct GalleryArchiveHeader: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(GalleryTheme.accent)
                .frame(width: 3)
                .frame(minHeight: 72, alignment: .top)

            VStack(alignment: .leading, spacing: 8) {
                Text("SYSTEM OUTPUT // ARCHIVE")
                    .font(.caption2.monospaced())
                    .foregroundStyle(GalleryTheme.accent)
                Text("COLLECTED WORKS")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(GalleryTheme.headline)
                Text("Visual computations rendered through mechanical character matrices. Stored in high-fidelity charcoal substrate.")
                    .font(.subheadline)
                    .foregroundStyle(GalleryTheme.bodyMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .padding(.bottom, 8)
    }
}

private struct GalleryNewArchivePlaceholder: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(GalleryTheme.accent.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [7, 6]))
                    .foregroundStyle(Color.white.opacity(0.2))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New archive")
    }
}

// MARK: - Masonry card

private struct GalleryMasonryCard: View {
    let entry: ArtworkIndexEntry
    let columnWidth: CGFloat
    var previewImage: CGImage?

    @EnvironmentObject private var library: ArtworkLibrary

    private var aspect: CGFloat {
        CGFloat(entry.canvasWidth) / CGFloat(max(1, entry.canvasHeight))
    }

    private var imageHeight: CGFloat {
        columnWidth / max(0.01, aspect)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artworkImage
                .frame(width: columnWidth, height: imageHeight)
                .clipped()

            VStack(alignment: .leading, spacing: 6) {
                Text(GalleryArchiveNaming.displayTitle(titlePrefix: entry.titlePrefix, for: entry.id))
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(GalleryTheme.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)

                Text(Self.formattedArchiveDate(entry.createdAt))
                    .font(.caption2.monospaced())
                    .foregroundStyle(GalleryTheme.bodyMuted)
            }
            .padding(12)
        }
        .background(GalleryTheme.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(GalleryArchiveNaming.displayTitle(titlePrefix: entry.titlePrefix, for: entry.id)), \(Self.formattedArchiveDate(entry.createdAt))")
    }

    private var artworkImage: some View {
        Group {
            if let preview = previewImage {
                Image(decorative: preview, scale: 1.0)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
            } else {
                AsyncImage(url: library.thumbURL(for: entry.id)) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .overlay { ProgressView() }
                    case .success(let image):
                        image
                            .resizable()
                            .interpolation(.none)
                            .scaledToFill()
                    case .failure:
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
    }

    private static let archiveDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM dd, yyyy"
        return f
    }()

    private static func formattedArchiveDate(_ date: Date) -> String {
        archiveDateFormatter.string(from: date).uppercased()
    }
}
