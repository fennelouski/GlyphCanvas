//
//  GalleryView.swift
//  GlyphCanvas
//

import SwiftUI

struct GalleryView: View {
    @EnvironmentObject private var library: ArtworkLibrary
    @Binding var mainTab: MainTab
    @Binding var studioAutoPresentImagePicker: Bool

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
                                    NavigationLink(value: AppRoute.detail(entry.id)) {
                                        GalleryMasonryCard(entry: entry, columnWidth: columnWidth)
                                    }
                                    .buttonStyle(.plain)
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
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(GalleryTheme.accent.opacity(0.75))
                Text("INITIALIZE NEW ARCHIVE")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(GalleryTheme.hudDetail)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [7, 6]))
                    .foregroundStyle(Color.white.opacity(0.2))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Initialize new archive")
    }
}

// MARK: - Masonry card

private struct GalleryMasonryCard: View {
    let entry: ArtworkIndexEntry
    let columnWidth: CGFloat

    @EnvironmentObject private var library: ArtworkLibrary

    private var aspect: CGFloat {
        CGFloat(entry.canvasWidth) / CGFloat(max(1, entry.canvasHeight))
    }

    private var imageHeight: CGFloat {
        columnWidth / max(0.01, aspect)
    }

    var body: some View {
        let tag = GalleryArchiveNaming.statusTag(for: entry.id)
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                artworkImage
                    .frame(width: columnWidth, height: imageHeight)
                    .clipped()

                statusTag(text: tag.text, isLocked: tag.isLocked)
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(GalleryArchiveNaming.compositionTitle(for: entry.id))
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(GalleryTheme.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Self.formattedArchiveDate(entry.createdAt))
                        .font(.caption2.monospaced())
                        .foregroundStyle(GalleryTheme.bodyMuted)
                    Spacer(minLength: 0)
                    Text("\(entry.glyphCount)")
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(GalleryTheme.accent.opacity(0.95))
                }
            }
            .padding(12)
        }
        .background(GalleryTheme.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(GalleryArchiveNaming.compositionTitle(for: entry.id)), \(Self.formattedArchiveDate(entry.createdAt))")
    }

    private var artworkImage: some View {
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

    private func statusTag(text: String, isLocked: Bool) -> some View {
        Text(text)
            .font(.caption2.monospaced().weight(.heavy))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isLocked
                    ? Color(red: 0.52, green: 0.2, blue: 0.2).opacity(0.92)
                    : GalleryTheme.accent.opacity(0.4),
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
            .foregroundStyle(isLocked ? Color.white : GalleryTheme.onAccentFill)
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
