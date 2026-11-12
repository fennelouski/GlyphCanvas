//
//  GlyphRevealAnimation.swift
//  GlyphCanvas
//
//  Decorative overlay that animates each newly committed glyph as it lands on the canvas.
//  The committed bitmap is unchanged; this only draws on top of it (not included in PNG/GIF export).
//

import CoreGraphics
import SwiftUI

nonisolated enum GlyphRevealStyle: String, CaseIterable, Identifiable, Sendable {
    case off, pop, drop, rise, spin, slam, ripple, sparkle, comet, wobble, glitch, glow, swirl, typewriter, rain, surprise

    static let storageKey = "glyphCanvas.glyphRevealStyle"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .off: "Off"
        case .pop: "Pop"
        case .drop: "Drop & Bounce"
        case .rise: "Float Up"
        case .spin: "Spin In"
        case .slam: "Slam"
        case .ripple: "Ripple"
        case .sparkle: "Sparkle"
        case .comet: "Comet"
        case .wobble: "Jelly"
        case .glitch: "Glitch"
        case .glow: "Glow"
        case .swirl: "Swirl"
        case .typewriter: "Typewriter"
        case .rain: "Rain"
        case .surprise: "Surprise Me"
        }
    }

    var systemImage: String {
        switch self {
        case .off: "circle.slash"
        case .pop: "sparkle"
        case .drop: "arrow.down.to.line"
        case .rise: "arrow.up"
        case .spin: "arrow.clockwise"
        case .slam: "arrow.down.right.and.arrow.up.left"
        case .ripple: "dot.radiowaves.left.and.right"
        case .sparkle: "sparkles"
        case .comet: "moon.stars"
        case .wobble: "waveform.path"
        case .glitch: "tv"
        case .glow: "sun.max"
        case .swirl: "tornado"
        case .typewriter: "keyboard"
        case .rain: "cloud.rain"
        case .surprise: "dice"
        }
    }

    /// Concrete styles `surprise` picks from.
    static let animated: [GlyphRevealStyle] = allCases.filter { $0 != .off && $0 != .surprise }

    /// `surprise` resolves to a stable per-glyph pick; other styles return themselves.
    func resolved(for sequenceIndex: Int) -> GlyphRevealStyle {
        guard self == .surprise else { return self }
        let all = Self.animated
        return all[Int(UInt64(truncatingIfNeeded: sequenceIndex) &* 2_654_435_761 % UInt64(all.count))]
    }

    /// Longest per-glyph animation `self` can produce.
    var maxDuration: Double {
        switch self {
        case .off: 0
        case .surprise: Self.animated.map(\.duration).max() ?? 0
        default: duration
        }
    }

    var duration: Double {
        switch self {
        case .rain, .comet, .swirl, .drop: 0.7
        case .typewriter, .glitch: 0.35
        default: 0.5
        }
    }
}

// MARK: - Pose math (pure; t is linear progress 0...1)

nonisolated struct GlyphRevealPose: Equatable {
    var scale: CGFloat = 1
    /// Offset in multiples of the glyph's font size (image pixels).
    var offset: CGSize = .zero
    var rotation: Double = 0
    var opacity: Double = 1
    var scaleY: CGFloat = 1
}

nonisolated enum GlyphRevealMath {
    static func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

    /// Damped spring that overshoots then settles at 1.
    static func spring(_ t: Double) -> Double { 1 - exp(-6 * t) * cos(12 * t) }

    static func bounce(_ t: Double) -> Double {
        let n = 7.5625, d = 2.75
        var x = t
        if x < 1 / d { return n * x * x }
        if x < 2 / d { x -= 1.5 / d; return n * x * x + 0.75 }
        if x < 2.5 / d { x -= 2.25 / d; return n * x * x + 0.9375 }
        x -= 2.625 / d
        return n * x * x + 0.984375
    }

    /// Fade the overlay out over the last 30% so it hands off to the committed glyph.
    static func tailFade(_ t: Double) -> Double { t < 0.7 ? 1 : max(0, (1 - t) / 0.3) }

    /// `fadeOut`: true on the live canvas (the committed glyph is underneath); false in video, where the overlay *is* the glyph.
    static func pose(_ style: GlyphRevealStyle, t rawT: Double, seed: UInt64, fadeOut: Bool = true) -> GlyphRevealPose {
        let t = min(1, max(0, rawT))
        var p = GlyphRevealPose()
        let fade = fadeOut ? tailFade(t) : 1
        switch style {
        case .off, .surprise:
            p.opacity = 0
        case .pop:
            p.scale = spring(t) * 1.6 - 0.6 * easeOut(t)
            p.opacity = fade
        case .drop:
            p.offset.height = -6 * (1 - bounce(t))
            p.opacity = fade
        case .rise:
            p.offset.height = 4 * (1 - easeOut(t))
            p.opacity = min(1, t * 3) * fade
        case .spin:
            p.rotation = 2 * .pi * (1 - easeOut(t))
            p.scale = 1 + 1.5 * (1 - easeOut(t))
            p.opacity = fade
        case .slam:
            p.scale = 1 + 4 * pow(1 - min(1, t * 2.2), 2)
            p.opacity = min(1, t * 4) * fade
        case .ripple, .sparkle, .glow:
            p.scale = 1 + 0.4 * (1 - easeOut(t))
            p.opacity = fade
        case .comet, .swirl:
            p.opacity = fade
        case .wobble:
            let damp = exp(-5 * t)
            p.scale = 1 + 0.6 * damp * sin(18 * t)
            p.rotation = 0.5 * damp * sin(14 * t)
            p.opacity = fade
        case .glitch:
            let step = Int(t * 8)
            var rng = SplitMix(seed: seed &+ UInt64(step))
            let amp = 1 - t
            p.offset = CGSize(width: rng.unit() * 1.5 * amp, height: rng.unit() * 0.6 * amp)
            p.opacity = fade
        case .typewriter:
            p.scaleY = 1 - 0.45 * sin(.pi * min(1, t * 2))
            p.scale = 1 + 0.3 * (1 - t)
            p.offset.height = -0.8 * (1 - easeOut(min(1, t * 2)))
            p.opacity = fade
        case .rain:
            p.offset.height = -30 * (1 - t * t)
            p.offset.width = -3 * (1 - t * t)
            p.opacity = min(1, t * 5) * fade
        }
        return p
    }
}

/// Tiny deterministic RNG so per-glyph randomness is stable across frames.
nonisolated struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// -1...1
    mutating func unit() -> CGFloat { CGFloat(Double(next() >> 11) / Double(1 << 53)) * 2 - 1 }
}

// MARK: - Overlay view

/// Sits on top of the fitted mosaic image. `recentGlyphs` are the last few *visible* operations, oldest first.
struct GlyphRevealOverlay: View {
    let recentGlyphs: [GlyphOperation]
    let imagePixelWidth: Int

    @AppStorage(GlyphRevealStyle.storageKey) private var storedStyle = GlyphRevealStyle.pop.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var store = Store()
    @State private var animatingUntil = Date.distantPast
    @State private var isAnimating = false

    /// ponytail: caps on-screen animations; at 120 glyphs/s older ones are dropped rather than queued.
    private static let maxActive = 48

    final class Store {
        struct Entry {
            let op: GlyphOperation
            let style: GlyphRevealStyle
            let birth: Date
            let from: CGPoint?
        }
        var entries: [Entry] = []
        var lastSeenIndex: Int?
        var bitmaps: [Int: CGImage] = [:]

        func bitmap(for op: GlyphOperation) -> CGImage? {
            if let b = bitmaps[op.sequenceIndex] { return b }
            // Render at 4× so the overlay stays crisp when the canvas is scaled up on screen.
            let b = ImageProcessing.renderGlyphBitmap(
                character: op.character,
                fontSize: op.fontSize * GlyphRevealOverlay.bitmapScale,
                rotationRadians: op.rotationRadians,
                color: op.color,
                isBold: op.isBold
            )
            bitmaps[op.sequenceIndex] = b
            return b
        }

        func prune(now: Date) {
            entries.removeAll { now.timeIntervalSince($0.birth) > $0.style.duration }
            if entries.isEmpty { bitmaps.removeAll() }
        }
    }

    static let bitmapScale: CGFloat = 4

    private var style: GlyphRevealStyle {
        reduceMotion ? .off : (GlyphRevealStyle(rawValue: storedStyle) ?? .pop)
    }

    var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            Canvas { ctx, size in
                draw(in: &ctx, size: size, now: timeline.date)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: recentGlyphs.last?.sequenceIndex) { _, _ in ingest() }
        .task(id: animatingUntil) {
            let wait = animatingUntil.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            if !Task.isCancelled { isAnimating = false }
        }
    }

    private func ingest() {
        let previous = store.lastSeenIndex
        store.lastSeenIndex = recentGlyphs.last?.sequenceIndex
        guard style != .off, let previous, let latest = recentGlyphs.last?.sequenceIndex else { return }
        // Only animate forward steps that fit in the window (skip scrubs, restarts, big jumps).
        guard latest > previous, latest - previous <= recentGlyphs.count else { return }

        let now = Date()
        var maxDuration = 0.0
        for (i, op) in recentGlyphs.enumerated() where op.sequenceIndex > previous {
            let s = style.resolved(for: op.sequenceIndex)
            let from = i > 0 ? recentGlyphs[i - 1].position : nil
            store.entries.append(.init(op: op, style: s, birth: now, from: from))
            maxDuration = max(maxDuration, s.duration)
        }
        if store.entries.count > Self.maxActive {
            store.entries.removeFirst(store.entries.count - Self.maxActive)
        }
        animatingUntil = now.addingTimeInterval(maxDuration)
        isAnimating = true
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, now: Date) {
        store.prune(now: now)
        guard !store.entries.isEmpty, imagePixelWidth > 0 else { return }
        let k = size.width / CGFloat(imagePixelWidth)

        for e in store.entries {
            let t = now.timeIntervalSince(e.birth) / e.style.duration
            guard let bitmap = store.bitmap(for: e.op) else { continue }
            let seed = UInt64(truncatingIfNeeded: e.op.sequenceIndex)
            let pose = GlyphRevealMath.pose(e.style, t: t, seed: seed)
            let fs = e.op.fontSize * k
            var center = CGPoint(x: e.op.position.x * k, y: e.op.position.y * k)
            let tint = Color(cgColor: e.op.color.cgColor)

            switch e.style {
            case .comet:
                if let from = e.from {
                    let u = GlyphRevealMath.easeOut(t)
                    let start = CGPoint(x: from.x * k, y: from.y * k)
                    let head = CGPoint(x: start.x + (center.x - start.x) * u, y: start.y + (center.y - start.y) * u)
                    let tailU = GlyphRevealMath.easeOut(max(0, t - 0.15))
                    let tail = CGPoint(x: start.x + (center.x - start.x) * tailU, y: start.y + (center.y - start.y) * tailU)
                    var path = Path()
                    path.move(to: tail)
                    path.addLine(to: head)
                    ctx.stroke(path, with: .color(tint.opacity(0.7 * pose.opacity)),
                               style: StrokeStyle(lineWidth: max(1, fs * 0.25), lineCap: .round))
                    center = head
                }
            case .swirl:
                let r = fs * 5 * (1 - GlyphRevealMath.easeOut(t))
                let a = Double(seed % 628) / 100 + 3 * .pi * t
                center.x += r * cos(a)
                center.y += r * sin(a)
            case .ripple:
                for ring in 0..<2 {
                    let rt = t - Double(ring) * 0.2
                    guard rt > 0 else { continue }
                    let radius = fs * (0.4 + 3 * GlyphRevealMath.easeOut(rt))
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                        with: .color(tint.opacity(0.8 * (1 - rt))),
                        lineWidth: max(0.75, fs * 0.12)
                    )
                }
            case .sparkle:
                var rng = SplitMix(seed: seed)
                for _ in 0..<6 {
                    let angle = Double(rng.unit()) * .pi
                    let dist = fs * (0.5 + 2.5 * GlyphRevealMath.easeOut(t)) * (0.7 + 0.3 * abs(rng.unit()))
                    let dot = max(1, fs * 0.18 * (1 - t))
                    let p = CGPoint(x: center.x + dist * cos(angle), y: center.y + dist * sin(angle))
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)),
                             with: .color(.white.opacity(0.9 * (1 - t))))
                }
            case .glitch:
                let splits: [(CGFloat, Color)] = [(-0.35, .red), (0.35, .cyan)]
                for (dx, c) in splits {
                    var layer = ctx
                    layer.opacity = 0.6 * pose.opacity
                    layer.addFilter(.colorMultiply(c))
                    let x: CGFloat = center.x + (pose.offset.width + dx) * fs
                    drawBitmap(bitmap, in: &layer, at: CGPoint(x: x, y: center.y), pose: pose, k: k)
                }
            case .glow:
                var layer = ctx
                layer.opacity = pose.opacity
                layer.addFilter(.blur(radius: fs * 0.6 * (1 - t) + 1))
                layer.addFilter(.brightness(0.4))
                drawBitmap(bitmap, in: &layer, at: center, pose: GlyphRevealPose(scale: pose.scale * 1.8), k: k)
            default:
                break
            }

            var layer = ctx
            layer.opacity = pose.opacity
            let at = CGPoint(x: center.x + pose.offset.width * fs, y: center.y + pose.offset.height * fs)
            drawBitmap(bitmap, in: &layer, at: at, pose: pose, k: k)
        }
    }

    private func drawBitmap(_ bitmap: CGImage, in ctx: inout GraphicsContext, at point: CGPoint, pose: GlyphRevealPose, k: CGFloat) {
        let w = CGFloat(bitmap.width) / Self.bitmapScale * k
        let h = CGFloat(bitmap.height) / Self.bitmapScale * k
        ctx.translateBy(x: point.x, y: point.y)
        ctx.rotate(by: .radians(pose.rotation))
        ctx.scaleBy(x: pose.scale, y: pose.scale * pose.scaleY)
        ctx.draw(Image(decorative: bitmap, scale: 1), in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
    }
}

// MARK: - Picker

struct GlyphRevealStyleMenu: View {
    @AppStorage(GlyphRevealStyle.storageKey) private var storedStyle = GlyphRevealStyle.pop.rawValue

    var body: some View {
        Menu {
            Picker("Glyph animation", selection: $storedStyle) {
                ForEach(GlyphRevealStyle.allCases) { style in
                    Label(style.title, systemImage: style.systemImage).tag(style.rawValue)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: (GlyphRevealStyle(rawValue: storedStyle) ?? .pop).systemImage)
                .frame(width: 22, height: 22)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .accessibilityLabel("Glyph animation")
    }
}
