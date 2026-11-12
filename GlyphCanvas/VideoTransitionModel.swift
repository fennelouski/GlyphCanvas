//
//  VideoTransitionModel.swift
//  GlyphCanvas
//
//  Edit decisions for a two-clip glyph transition. All times in seconds.
//  Output timeline: clip 1 plays from 0; glyphs build over it from `transitionStart`;
//  at `cut` clip 2 takes over and plays to `cut + clip2Length`.
//

import Foundation

nonisolated struct TransitionEdit: Equatable, Sendable {
    var clip1Duration: Double
    var clip2Duration: Double
    /// Source time in clip 1 that plays at output 0.
    var clip1In: Double = 0
    /// Output time where glyphs start landing on clip 1.
    var transitionStart: Double
    /// Output time where clip 2 starts. Must be within clip 1 (`<= clip1Available`).
    var cut: Double
    /// Source time in clip 2 shown at `cut`; this frame is what the glyphs build.
    var clip2In: Double = 0
    var clip2Out: Double
    var clip1Volume: Float = 1
    var clip2Volume: Float = 1
    /// Audio crossfade length starting at `cut`. Clip 1's audio keeps playing under clip 2 for this long when it has media left.
    var audioFade: Double = 1
    /// Fraction of the frame covered by glyphs at the cut.
    var coverage: Double = 0.85

    static let minGap = 0.2

    init(clip1Duration: Double, clip2Duration: Double) {
        self.clip1Duration = max(0.5, clip1Duration)
        self.clip2Duration = max(0.5, clip2Duration)
        cut = max(Self.minGap, self.clip1Duration - 1)
        transitionStart = max(0, cut - 2)
        clip2Out = self.clip2Duration
        clamp()
    }

    var clip1Available: Double { clip1Duration - clip1In }
    var clip2Length: Double { clip2Out - clip2In }
    var outputDuration: Double { cut + clip2Length }
    var clip1AudioTail: Double { max(0, min(audioFade, clip1Available - cut)) }
    var clip2FadeIn: Double { min(audioFade, clip2Length) }

    mutating func clamp() {
        let g = Self.minGap
        clip1In = min(max(0, clip1In), clip1Duration - 2 * g)
        cut = min(max(g, cut), clip1Available)
        transitionStart = min(max(0, transitionStart), cut - g)
        clip2In = min(max(0, clip2In), clip2Duration - g)
        clip2Out = min(max(clip2In + g, clip2Out), clip2Duration)
        audioFade = min(max(0, audioFade), 5)
        coverage = min(max(0.3, coverage), 1)
        clip1Volume = min(max(0, clip1Volume), 2)
        clip2Volume = min(max(0, clip2Volume), 2)
    }
}

/// When each planned glyph lands. Accelerates (slow trickle, then a rush) so the build feels like it's racing to the cut.
nonisolated enum GlyphTransitionPacing {
    static let exponent = 1.5

    /// Number of glyphs landed by output time `t` (fractional).
    static func revealed(at t: Double, total: Int, start: Double, cut: Double) -> Double {
        guard total > 0 else { return 0 }
        guard cut > start else { return t >= cut ? Double(total) : 0 }
        let p = min(1, max(0, (t - start) / (cut - start)))
        return Double(total) * pow(p, exponent)
    }

    /// Output time glyph `index` lands (inverse of `revealed`).
    static func birth(of index: Int, total: Int, start: Double, cut: Double) -> Double {
        start + (cut - start) * pow(Double(index + 1) / Double(max(1, total)), 1 / exponent)
    }
}
