//
//  GlyphCandidate.swift
//  GlyphCanvas
//
//  Created by Codex on 4/16/26.
//

import CoreGraphics
import Foundation

struct GlyphCandidate: Sendable {
    let character: String
    let fontSize: CGFloat
    let rotationRadians: CGFloat
    let color: RGBAColor
    let region: PixelRegion
    /// Pixel offset from region center (scratch / canvas space).
    var centerOffsetX: CGFloat = 0
    var centerOffsetY: CGFloat = 0
    /// When true, the typewriter font is drawn with a bold trait (Courier/Menlo).
    var isBold: Bool = false
}
