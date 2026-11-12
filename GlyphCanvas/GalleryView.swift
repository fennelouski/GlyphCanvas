//
//  GalleryView.swift
//  GlyphCanvas
//

import CoreGraphics
import SwiftUI

struct GalleryView: View {
    @Environment(\.appTheme) private var theme
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
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if geo.size.width >= 700 {
                        HStack(alignment: .top, spacing: 16) {
                            HomeCreateCard(action: startNewArtwork)
                            if let latest = latestEntry {
                                HomeContinueCard(entry: latest)
                            }
                        }
                    } else {
                        HomeCreateCard(action: startNewArtwork)
                        if let latest = latestEntry {
                            HomeContinueCard(entry: latest)
                        }
                    }
                    if library.entries.isEmpty {
                        HomeHowItWorks()
                    } else {
                        galleryGrid(width: min(geo.size.width, Self.maxContentWidth) - Self.horizontalPadding * 2)
                    }
                }
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: Self.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .background(theme.screenBackground)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .navigationTitle("Home")
        .refreshable {
            try? library.reloadFromDisk()
        }
        #if os(iOS)
        .fullScreenCover(item: $fullscreenItem) { item in
            fullscreenPlayer(item)
        }
        #else
        .sheet(item: $fullscreenItem) { item in
            fullscreenPlayer(item)
                .frame(minWidth: 720, minHeight: 560)
        }
        #endif
    }

    private static let horizontalPadding: CGFloat = 20
    private static let maxContentWidth: CGFloat = 1180

    private func fullscreenPlayer(_ item: GalleryFullscreenItem) -> some View {
        GalleryPlaybackFullscreenView(
            artworkID: item.id,
            isPresented: Binding(
                get: { fullscreenItem != nil },
                set: { if !$0 { fullscreenItem = nil } }
            )
        )
        .environmentObject(library)
    }

    private var latestEntry: ArtworkIndexEntry? {
        library.entries.max { $0.createdAt < $1.createdAt }
    }

    private func startNewArtwork() {
        studioAutoPresentImagePicker = true
        mainTab = .studio
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GlyphCanvas")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(GalleryTheme.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Turn any photo into art made of letters, numbers and emoji.")
                .font(.subheadline)
                .foregroundStyle(GalleryTheme.bodyMuted)
        }
        .padding(.top, 12)
    }

    // MARK: - Gallery (masonry)

    private func galleryGrid(width: CGFloat) -> some View {
        let spacing: CGFloat = 12
        let columnCount = max(2, Int(width / 220))
        let gutter = spacing * CGFloat(columnCount - 1)
        let columnWidth = max(72, (width - gutter) / CGFloat(columnCount))
        let columns = Self.splitIntoMasonryColumns(
            library.entries,
            columnCount: columnCount,
            columnWidth: columnWidth,
            spacing: spacing
        )
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Gallery")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(GalleryTheme.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("\(library.entries.count)")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(GalleryTheme.hudDetail)
                Spacer()
            }
            Text("Tap to open · press and hold to watch it draw")
                .font(.footnote)
                .foregroundStyle(GalleryTheme.bodyMuted)
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
        }
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

    private static func estimatedCardHeight(entry: ArtworkIndexEntry, columnWidth: CGFloat) -> CGFloat {
        let aspect = CGFloat(entry.canvasWidth) / CGFloat(max(1, entry.canvasHeight))
        return columnWidth / max(0.01, aspect) + cardFooterChrome
    }

    private static let cardFooterChrome: CGFloat = 64
}

// MARK: - Home cards

private struct HomeCreateCard: View {
    @Environment(\.appTheme) private var theme
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HeroMosaicBackground()
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text("New artwork")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(GalleryTheme.headline)
                Text("Pick a photo from your library, camera, files or a web link.")
                    .font(.subheadline)
                    .foregroundStyle(GalleryTheme.bodyMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: action) {
                    Label("Choose a Photo", systemImage: "photo.badge.plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct HomeContinueCard: View {
    @Environment(\.appTheme) private var theme
    let entry: ArtworkIndexEntry
    @EnvironmentObject private var library: ArtworkLibrary
    @EnvironmentObject private var navigationHistory: MacNavigationHistory

    private var title: String {
        GalleryArchiveNaming.displayTitle(titlePrefix: entry.titlePrefix, for: entry.id)
    }

    var body: some View {
        Button {
            navigationHistory.galleryPath.append(.editorResume(entry.id))
        } label: {
            HStack(spacing: 16) {
                AsyncImage(url: library.thumbURL(for: entry.id)) { image in
                    image.resizable().interpolation(.none).scaledToFill()
                } placeholder: {
                    theme.canvasBackdrop
                }
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Continue")
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(theme.accent)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(GalleryTheme.headline)
                        .lineLimit(2)
                    Text("\(entry.glyphCount) glyphs · \(entry.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(GalleryTheme.bodyMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(GalleryTheme.hudDetail)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue editing \(title)")
    }
}

private struct HomeHowItWorks: View {
    @Environment(\.appTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How it works")
                .font(.title2.weight(.bold))
                .foregroundStyle(GalleryTheme.headline)
                .accessibilityAddTraits(.isHeader)
            step("1", "photo", "Pick a photo", "Any image from Photos, the camera, Files or a link.")
            step("2", "slider.horizontal.3", "Shape it live", "Change detail, glyph size, color or the characters used. The preview redraws immediately.")
            step("3", "square.and.arrow.up", "Save and share", "Keep it in your gallery, export a PNG, or share an animated GIF of it being drawn.")
        }
        .padding(18)
        .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func step(_ number: String, _ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(theme.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(GalleryTheme.headline)
                Text(detail).font(.subheadline).foregroundStyle(GalleryTheme.bodyMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Step \(number)"))
    }
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

// MARK: - Masonry card

private struct GalleryMasonryCard: View {
    @Environment(\.appTheme) private var theme
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GalleryTheme.headline)
                    .lineLimit(2)

                Text(Self.formattedArchiveDate(entry.createdAt))
                    .font(.caption)
                    .foregroundStyle(GalleryTheme.bodyMuted)
            }
            .padding(10)
        }
        .background(theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                            .fill(theme.canvasBackdrop)
                            .overlay { ProgressView() }
                    case .success(let image):
                        image
                            .resizable()
                            .interpolation(.none)
                            .scaledToFill()
                    case .failure:
                        Rectangle()
                            .fill(theme.canvasBackdrop)
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

    private static func formattedArchiveDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
