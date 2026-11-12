//
//  TransitionTimelineView.swift
//  GlyphCanvas
//
//  Scrolling multi-track timeline: fixed center playhead, filmstrips, waveforms, trim handles.
//  Drag handles to trim; long-press the clip 2 block and drag to move the cut; pinch to zoom.
//

import SwiftUI

struct TransitionTimelineView: View {
    @Binding var edit: TransitionEdit
    let currentTime: Double
    let media1: ClipMedia?
    let media2: ClipMedia?
    let styleIcon: String
    var onScrub: (Double) -> Void
    var onScrubbingChanged: (Bool) -> Void

    @Environment(\.appTheme) private var theme

    /// Points per second of output time.
    @State private var pps: CGFloat = 0
    @State private var pinchBase: CGFloat?
    @State private var dragStart: TransitionEdit?
    @State private var position = ScrollPosition(edge: .leading)
    @State private var userScrolling = false

    private let rulerHeight: CGFloat = 18
    private let transitionHeight: CGFloat = 24
    private let trackHeight: CGFloat = 54
    private let spacing: CGFloat = 6

    private var totalHeight: CGFloat { rulerHeight + transitionHeight + trackHeight * 2 + spacing * 3 }

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let scale = pps > 0 ? pps : max(20, geo.size.width * 0.8 / max(1, edit.outputDuration))
            ScrollView(.horizontal, showsIndicators: false) {
                tracks(pps: scale)
                    .frame(width: max(1, max(edit.outputDuration, edit.clip1Available) * scale), height: totalHeight, alignment: .topLeading)
                    .padding(.horizontal, half)
            }
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, x in
                if userScrolling { onScrub(max(0, Double(x / scale))) }
            }
            .onScrollPhaseChange { _, phase in
                let scrolling = phase == .tracking || phase == .interacting || phase == .decelerating
                guard scrolling != userScrolling else { return }
                userScrolling = scrolling
                onScrubbingChanged(scrolling)
            }
            .onChange(of: currentTime) { _, t in
                if !userScrolling { position.scrollTo(x: t * scale) }
            }
            .onChange(of: scale) { _, s in position.scrollTo(x: currentTime * s) }
            .overlay {
                Rectangle()
                    .fill(.white)
                    .frame(width: 2)
                    .shadow(radius: 2)
                    .allowsHitTesting(false)
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let base = pinchBase ?? scale
                        pinchBase = base
                        pps = min(400, max(8, base * value.magnification))
                    }
                    .onEnded { _ in pinchBase = nil }
            )
        }
        .frame(height: totalHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline")
    }

    // MARK: Tracks

    private func tracks(pps: CGFloat) -> some View {
        let transitionY = rulerHeight + spacing
        let clip1Y = transitionY + transitionHeight + spacing
        let clip2Y = clip1Y + trackHeight + spacing
        return ZStack(alignment: .topLeading) {
            Ruler(pps: pps, duration: max(edit.outputDuration, edit.clip1Available))
                .frame(height: rulerHeight)

            // Glyph build segment
            HStack(spacing: 4) {
                Image(systemName: styleIcon)
                Text("Glyphs")
                    .lineLimit(1)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.leading, 16)
            .frame(width: max(24, (edit.cut - edit.transitionStart) * pps), height: transitionHeight, alignment: .leading)
            .background(theme.accent.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .leading) {
                TrimHandle(height: transitionHeight).gesture(drag(pps: pps) { e, d in e.transitionStart += d })
            }
            .offset(x: edit.transitionStart * pps, y: transitionY)
            .accessibilityElement()
            .accessibilityLabel("Glyph transition")
            .accessibilityValue("Starts at \(edit.transitionStart, specifier: "%.1f") seconds")
            .accessibilityAdjustableAction { direction in
                adjust(direction) { e, d in e.transitionStart += d }
            }

            // Clip 1 (background). Past the cut it's dimmed: only its audio tail plays there.
            ClipStrip(media: media1, sourceStart: edit.clip1In, pps: pps, volume: edit.clip1Volume, tint: .blue)
                .frame(width: edit.clip1Available * pps, height: trackHeight)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(.black.opacity(0.55))
                        .frame(width: max(0, (edit.clip1Available - edit.cut) * pps))
                        .offset(x: edit.cut * pps)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .leading) {
                    TrimHandle(height: trackHeight).gesture(drag(pps: pps) { e, d in e.clip1In += d })
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .offset(y: clip1Y)
                .accessibilityElement()
                .accessibilityLabel("Background clip")
                .accessibilityValue("Starts \(edit.clip1In, specifier: "%.1f") seconds into the clip")
                .accessibilityAdjustableAction { direction in
                    adjust(direction) { e, d in e.clip1In += d }
                }

            // Clip 2 (incoming), placed at the cut.
            ClipStrip(media: media2, sourceStart: edit.clip2In, pps: pps, volume: edit.clip2Volume, tint: .orange)
                .frame(width: edit.clip2Length * pps, height: trackHeight)
                .overlay(alignment: .leading) {
                    TrimHandle(height: trackHeight).gesture(drag(pps: pps) { e, d in
                        let applied = min(max(d, -e.clip2In), e.clip2Length - TransitionEdit.minGap)
                        e.clip2In += applied
                        e.cut += applied
                    })
                }
                .overlay(alignment: .trailing) {
                    TrimHandle(height: trackHeight).gesture(drag(pps: pps) { e, d in e.clip2Out += d })
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .gesture(moveCutGesture(pps: pps))
                .offset(x: edit.cut * pps, y: clip2Y)
                .accessibilityElement()
                .accessibilityLabel("Incoming clip")
                .accessibilityValue("Starts at \(edit.cut, specifier: "%.1f") seconds")
                .accessibilityAdjustableAction { direction in
                    adjust(direction) { e, d in e.cut += d }
                }
        }
    }

    // MARK: Gestures

    private func drag(pps: CGFloat, _ apply: @escaping (inout TransitionEdit, Double) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStart ?? edit
                dragStart = start
                var e = start
                apply(&e, Double(value.translation.width / pps))
                e.clamp()
                edit = e
            }
            .onEnded { _ in dragStart = nil }
    }

    private func moveCutGesture(pps: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                let start = dragStart ?? edit
                dragStart = start
                var e = start
                let delta = Double(drag.translation.width / pps)
                e.cut += delta
                e.transitionStart += delta
                e.clamp()
                edit = e
            }
            .onEnded { _ in dragStart = nil }
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection, _ apply: (inout TransitionEdit, Double) -> Void) {
        var e = edit
        switch direction {
        case .increment: apply(&e, 0.1)
        case .decrement: apply(&e, -0.1)
        @unknown default: return
        }
        e.clamp()
        edit = e
    }
}

// MARK: - Pieces

private struct TrimHandle: View {
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.white)
            .frame(width: 12, height: height)
            .overlay {
                Capsule().fill(.black.opacity(0.5)).frame(width: 2, height: height * 0.4)
            }
            .contentShape(Rectangle().inset(by: -8))
            .accessibilityHidden(true)
    }
}

private struct Ruler: View {
    let pps: CGFloat
    let duration: Double

    var body: some View {
        Canvas { ctx, size in
            let step: Double = pps < 25 ? 5 : (pps < 70 ? 1 : 0.5)
            var t = 0.0
            while t <= duration {
                let x = t * pps
                let major = t.truncatingRemainder(dividingBy: step * 2) == 0
                ctx.fill(Path(CGRect(x: x, y: major ? 8 : 12, width: 1, height: major ? 10 : 6)), with: .color(.secondary))
                if major {
                    ctx.draw(Text(Self.label(t)).font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary),
                             at: CGPoint(x: x + 3, y: 4), anchor: .leading)
                }
                t += step
            }
        }
        .allowsHitTesting(false)
    }

    static func label(_ t: Double) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Filmstrip on top, waveform underneath. Chunked into lazily drawn tiles so long clips don't make one giant layer.
private struct ClipStrip: View {
    let media: ClipMedia?
    let sourceStart: Double
    let pps: CGFloat
    let volume: Float
    let tint: Color

    private let chunk: CGFloat = 600

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let chunks = max(1, Int((width / chunk).rounded(.up)))
            LazyHStack(spacing: 0) {
                ForEach(0..<chunks, id: \.self) { i in
                    let x0 = CGFloat(i) * chunk
                    Canvas { ctx, size in
                        draw(&ctx, size: size, x0: x0)
                    }
                    .frame(width: min(chunk, width - x0), height: geo.size.height)
                }
            }
        }
        .background(tint.opacity(0.35))
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, x0: CGFloat) {
        let filmHeight = size.height * 0.66
        if let media, !media.thumbnails.isEmpty {
            let tileW = max(8, filmHeight * media.aspect)
            var x = -(x0.truncatingRemainder(dividingBy: tileW))
            while x < size.width {
                let t = sourceStart + Double(x0 + x + tileW / 2) / pps
                let i = min(media.thumbnails.count - 1, max(0, Int(t / media.thumbnailInterval)))
                ctx.draw(Image(decorative: media.thumbnails[i], scale: 1), in: CGRect(x: x, y: 0, width: tileW, height: filmHeight))
                x += tileW
            }
        }
        let waveTop = filmHeight
        let waveH = size.height - filmHeight
        ctx.fill(Path(CGRect(x: 0, y: waveTop, width: size.width, height: waveH)), with: .color(.black.opacity(0.45)))
        guard let peaks = media?.peaks, !peaks.isEmpty else { return }
        let gain = CGFloat(min(1, volume))
        var path = Path()
        var x: CGFloat = 0
        while x < size.width {
            let t = sourceStart + Double(x0 + x) / pps
            let i = Int(t * Double(ClipMedia.peaksPerSecond))
            if i >= 0, i < peaks.count {
                let h = max(1, CGFloat(peaks[i]) * gain * (waveH - 4))
                path.addRect(CGRect(x: x, y: waveTop + (waveH - h) / 2, width: 1.5, height: h))
            }
            x += 2.5
        }
        ctx.fill(path, with: .color(tint))
    }
}
