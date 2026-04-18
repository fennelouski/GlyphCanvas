//
//  LandingEmptyStateView.swift
//  GlyphCanvas
//

import CoreGraphics
import SwiftUI

struct LandingEmptyStateView: View {
    @Binding var mainTab: MainTab
    @Binding var studioAutoPresentImagePicker: Bool

    var body: some View {
        VStack(spacing: 0) {
            landingHeader
            ScrollView {
                VStack(spacing: 24) {
                    heroSection
                    textBlock
                    actionButtons
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            landingMetadataFooter
        }
        .background(GalleryTheme.background)
    }

    private var landingHeader: some View {
        HStack(spacing: 12) {
            Menu {
                Button("About GlyphCanvas") {}
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(GalleryTheme.accent)
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Menu")

            Spacer(minLength: 0)

            Text("ART GALLERY")
                .font(.subheadline.weight(.heavy))
                .tracking(1.2)
                .foregroundStyle(GalleryTheme.accent)

            Spacer(minLength: 0)

            Image(systemName: "gearshape.fill")
                .font(.system(size: 28))
                .foregroundStyle(GalleryTheme.accent)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Settings")
                .onTapGesture { mainTab = .settings }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var heroSection: some View {
        ZStack(alignment: .topLeading) {
            HeroMosaicBackground()
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    systemReadyBadge
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .padding(16)

            VStack(alignment: .leading, spacing: 4) {
                hudLine("STATUS: IDLE WAITING")
                hudLine("BUFFER: 0.00KB")
                hudLine("GRID: 120×120")
            }
            .font(.caption2.monospaced())
            .foregroundStyle(GalleryTheme.hudDetail)
            .padding(12)
        }
        .frame(maxWidth: .infinity)
    }

    private var landingMetadataFooter: some View {
        VStack(alignment: .trailing, spacing: 4) {
            hudLine("TYPE: ASCII METAL")
            hudLine("PROCESS: ANALOG CONVERSION")
            Text("V.\(GalleryTheme.marketingVersion)")
                .font(.caption2.monospaced())
                .foregroundStyle(GalleryTheme.hudAccent)
        }
        .font(.caption2.monospaced())
        .foregroundStyle(GalleryTheme.hudDetail)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var systemReadyBadge: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(GalleryTheme.accent.opacity(0.95))
                    .frame(width: 56, height: 56)
                Image(systemName: "square.grid.2x2.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(GalleryTheme.onAccentFill)
            }
            Text("SYSTEM READY")
                .font(.caption.weight(.heavy))
                .tracking(1.0)
                .foregroundStyle(GalleryTheme.accent)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 28)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func hudLine(_ text: String) -> some View {
        Text(text)
    }

    private var textBlock: some View {
        VStack(spacing: 12) {
            Text("Your Canvas is Empty")
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(GalleryTheme.headline)
            Text("Turn your photos into mechanical masterpieces. Start by uploading an image to see the typewriter effect in action.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(GalleryTheme.bodyMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var actionButtons: some View {
        Button {
            studioAutoPresentImagePicker = true
            mainTab = .studio
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "photo.badge.plus")
                    .font(.body.weight(.semibold))
                Text("NEW MOSAIC")
                    .font(.subheadline.weight(.heavy))
                    .tracking(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(GalleryTheme.onAccentFill)
            .background(GalleryTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hero mosaic (progressive logo encoding)

/// Raster preview matching `systemReadyBadge`: accent tile + `square.grid.2x2.fill` in `onAccentFill`.
private struct HeroLogoMaskSourceView: View {
    private let side: CGFloat = 256

    private var cornerRadius: CGFloat { 12 * side / 56 }

    private var symbolPointSize: CGFloat { 22 * side / 56 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(GalleryTheme.accent.opacity(0.95))
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: symbolPointSize, weight: .semibold))
                .foregroundStyle(GalleryTheme.onAccentFill)
        }
        .frame(width: side, height: side)
    }
}

/// Byte buffer of premultiplied RGBA samples from a `CGImage` (sRGB).
private enum HeroLogoMaskBitmapFactory {
    static func rgbaData(cgImage: CGImage, width w: Int, height h: Int, bytesPerRow: Int) -> Data? {
        let byteCount = h * bytesPerRow
        var rawBytes = [UInt8](repeating: 0, count: byteCount)
        let ok: Bool = rawBytes.withUnsafeMutableBytes { raw in
            guard let ptr = raw.baseAddress,
                  let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(
                      data: ptr,
                      width: w,
                      height: h,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        return Data(rawBytes)
    }
}

private struct HeroLogoMaskBitmap: Sendable {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    private let storage: Data

    init?(cgImage: CGImage) {
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return nil }
        let bpr = w * 4
        guard let data = HeroLogoMaskBitmapFactory.rgbaData(cgImage: cgImage, width: w, height: h, bytesPerRow: bpr) else {
            return nil
        }
        width = w
        height = h
        bytesPerRow = bpr
        storage = data
    }

    /// Normalized UV; `ny` is top row = 0 (screen-like).
    func luminance(nx: CGFloat, ny: CGFloat) -> Double {
        let xf = min(width - 1, max(0, Int(nx * CGFloat(width - 1))))
        let yf = min(height - 1, max(0, Int(ny * CGFloat(height - 1))))
        let o = yf * bytesPerRow + xf * 4
        guard o + 2 < storage.count else { return 1 }
        let r = Double(storage[o]) / 255
        let g = Double(storage[o + 1]) / 255
        let b = Double(storage[o + 2]) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

@MainActor
private enum HeroLogoMaskFactory {
    private static var cachedBitmap: HeroLogoMaskBitmap?

    static func makeBitmap() -> HeroLogoMaskBitmap? {
        if let cachedBitmap {
            return cachedBitmap
        }
        let view = HeroLogoMaskSourceView()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else { return nil }
        let bitmap = HeroLogoMaskBitmap(cgImage: cgImage)
        cachedBitmap = bitmap
        return bitmap
    }
}

private struct HeroMosaicBackground: View {
    /// JPEG-style 8×8 zigzag: raster index → order within block (0…63).
    private static let jpegRasterToZigzagRank: [Int] = {
        let zigToRaster = [
            0, 1, 8, 16, 9, 2, 3, 10,
            17, 24, 32, 25, 18, 11, 4, 5,
            12, 19, 26, 33, 40, 48, 41, 34,
            27, 20, 13, 6, 7, 14, 21, 28,
            35, 42, 49, 56, 57, 50, 43, 36,
            29, 22, 15, 23, 30, 37, 44, 51,
            58, 59, 52, 45, 38, 31, 39, 46,
            53, 60, 61, 54, 47, 55, 62, 63,
        ]
        var inv = [Int](repeating: 0, count: 64)
        for (rank, raster) in zigToRaster.enumerated() {
            inv[raster] = rank
        }
        return inv
    }()

    private static let accentRGB = (r: 126.0 / 255.0, g: 177.0 / 255.0, b: 1.0)
    private static let inkLuminanceThreshold = 0.42
    private static let decodeProgress: Double = 0.72

    @State private var maskBitmap: HeroLogoMaskBitmap?

    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 5
            let cols = max(1, Int(ceil(size.width / cell)))
            let rows = max(1, Int(ceil(size.height / cell)))
            let totalCells = cols * rows
            let threshold = Int(Double(totalCells) * Self.decodeProgress)
            let blocksW = (cols + 7) / 8
            var state: UInt64 = 0xBEEF_1234_CAFE

            for iy in 0..<rows {
                for ix in 0..<cols {
                    let x = CGFloat(ix) * cell
                    let y = CGFloat(iy) * cell
                    let rect = CGRect(
                        x: x,
                        y: y,
                        width: min(cell, size.width - x),
                        height: min(cell, size.height - y)
                    )

                    let blockX = ix / 8
                    let blockY = iy / 8
                    let lx = ix % 8
                    let ly = iy % 8
                    let rasterLocal = ly * 8 + lx
                    let zigRank = Self.jpegRasterToZigzagRank[rasterLocal]
                    let blockIndex = blockY * blocksW + blockX
                    let decodeIndex = blockIndex * 64 + zigRank

                    let nx = (CGFloat(ix) + 0.5) / CGFloat(cols)
                    let ny = (CGFloat(iy) + 0.5) / CGFloat(rows)

                    let fill: Color
                    if decodeIndex > threshold {
                        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                        let t = Double(state % 2048) / 2047.0
                        let jitter = (t - 0.5) * 0.14
                        let r = min(1, max(0, Self.accentRGB.r * (1 + jitter)))
                        let g = min(1, max(0, Self.accentRGB.g * (1 + jitter)))
                        let b = min(1, max(0, Self.accentRGB.b * (1 + jitter * 0.85)))
                        fill = Color(red: r, green: g, blue: b)
                    } else if let mask = maskBitmap {
                        // Bitmap rows follow Core Graphics (y up); UV is top-down for the hero.
                        let lum = mask.luminance(nx: nx, ny: 1.0 - ny)
                        let isInk = lum < Self.inkLuminanceThreshold
                        fill = isInk ? GalleryTheme.onAccentFill : GalleryTheme.accent
                    } else {
                        fill = GalleryTheme.accent
                    }

                    context.fill(Path(rect), with: .color(fill))
                }
            }
        }
        .background(GalleryTheme.accent)
        .task {
            guard maskBitmap == nil else { return }
            maskBitmap = HeroLogoMaskFactory.makeBitmap()
        }
    }
}
