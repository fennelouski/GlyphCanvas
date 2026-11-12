//
//  HomeHeroMosaic.swift
//  GlyphCanvas
//

import SwiftUI

/// Animated app mark: cells "decode" block by block in JPEG zigzag order, like glyphs landing on the canvas.
struct HeroMosaicBackground: View {
    @Environment(\.appTheme) private var theme
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

    /// Seconds per cycle: decode, then hold the finished mark for 1.5 s.
    private static let cycle: Double = 7

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.cycle)
            mosaic(progress: reduceMotion ? 1 : min(1, t / (Self.cycle - 1.5)))
        }
        .accessibilityHidden(true)
    }

    private func mosaic(progress: Double) -> some View {
        Canvas { context, size in
            let cell = max(3, size.width / 26)
            let cols = max(1, Int(ceil(size.width / cell)))
            let rows = max(1, Int(ceil(size.height / cell)))
            let threshold = Int(Double(cols * rows) * progress)
            let blocksW = (cols + 7) / 8
            var state: UInt64 = 0xBEEF_1234_CAFE
            var decoded = Path()

            for iy in 0..<rows {
                for ix in 0..<cols {
                    let rect = CGRect(x: CGFloat(ix) * cell, y: CGFloat(iy) * cell, width: cell, height: cell)
                    let blockIndex = (iy / 8) * blocksW + ix / 8
                    let decodeIndex = blockIndex * 64 + Self.jpegRasterToZigzagRank[(iy % 8) * 8 + ix % 8]
                    if decodeIndex <= threshold {
                        decoded.addRect(rect)
                    } else {
                        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                        let t = Double(state % 2048) / 2047.0
                        context.fill(Path(rect), with: .color(theme.accent.opacity(0.12 + t * 0.18)))
                    }
                }
            }

            // Decoded cells reveal the finished mark.
            context.clip(to: decoded)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(theme.accent))
            let symbol = context.resolve(
                Image(systemName: "character.textbox").renderingMode(.template)
            )
            var tinted = symbol
            tinted.shading = .color(GalleryTheme.onAccentFill)
            let side = size.width * 0.58
            context.draw(
                tinted,
                in: CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            )
        }
    }
}
