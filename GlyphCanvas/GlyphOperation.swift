//
//  GlyphOperation.swift
//  GlyphCanvas
//

import CoreGraphics
import Foundation

/// Lightweight record of one committed glyph for timeline replay (no bitmap storage).
struct GlyphOperation: Sendable, Codable {
    let character: String
    /// Exact draw center used by `ImageProcessing.drawGlyph` (region center ± offsets).
    let position: CGPoint
    let fontSize: CGFloat
    let rotationRadians: CGFloat
    let color: RGBAColor
    let region: PixelRegion
    let centerOffsetX: CGFloat
    let centerOffsetY: CGFloat
    /// 0-based index at commit time (stable across replay).
    let sequenceIndex: Int
    let isBold: Bool

    nonisolated func makeCandidate() -> GlyphCandidate {
        GlyphCandidate(
            character: character,
            fontSize: fontSize,
            rotationRadians: rotationRadians,
            color: color,
            region: region,
            centerOffsetX: centerOffsetX,
            centerOffsetY: centerOffsetY,
            isBold: isBold
        )
    }

    init(
        character: String,
        position: CGPoint,
        fontSize: CGFloat,
        rotationRadians: CGFloat,
        color: RGBAColor,
        region: PixelRegion,
        centerOffsetX: CGFloat,
        centerOffsetY: CGFloat,
        sequenceIndex: Int,
        isBold: Bool = false
    ) {
        self.character = character
        self.position = position
        self.fontSize = fontSize
        self.rotationRadians = rotationRadians
        self.color = color
        self.region = region
        self.centerOffsetX = centerOffsetX
        self.centerOffsetY = centerOffsetY
        self.sequenceIndex = sequenceIndex
        self.isBold = isBold
    }

    init(from candidate: GlyphCandidate, sequenceIndex: Int) {
        let center = CGPoint(
            x: CGFloat(candidate.region.x) + CGFloat(candidate.region.width) / 2.0 + candidate.centerOffsetX,
            y: CGFloat(candidate.region.y) + CGFloat(candidate.region.height) / 2.0 + candidate.centerOffsetY
        )
        self.init(
            character: candidate.character,
            position: center,
            fontSize: candidate.fontSize,
            rotationRadians: candidate.rotationRadians,
            color: candidate.color,
            region: candidate.region,
            centerOffsetX: candidate.centerOffsetX,
            centerOffsetY: candidate.centerOffsetY,
            sequenceIndex: sequenceIndex,
            isBold: candidate.isBold
        )
    }

    private enum CodingKeys: String, CodingKey {
        case character
        case positionX
        case positionY
        case fontSize
        case rotationRadians
        case color
        case region
        case centerOffsetX
        case centerOffsetY
        case sequenceIndex
        case isBold
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        character = try c.decode(String.self, forKey: .character)
        let px = try c.decode(Double.self, forKey: .positionX)
        let py = try c.decode(Double.self, forKey: .positionY)
        position = CGPoint(x: px, y: py)
        fontSize = CGFloat(try c.decode(Double.self, forKey: .fontSize))
        rotationRadians = CGFloat(try c.decode(Double.self, forKey: .rotationRadians))
        color = try c.decode(RGBAColor.self, forKey: .color)
        region = try c.decode(PixelRegion.self, forKey: .region)
        centerOffsetX = CGFloat(try c.decode(Double.self, forKey: .centerOffsetX))
        centerOffsetY = CGFloat(try c.decode(Double.self, forKey: .centerOffsetY))
        sequenceIndex = try c.decode(Int.self, forKey: .sequenceIndex)
        isBold = try c.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(character, forKey: .character)
        try c.encode(Double(position.x), forKey: .positionX)
        try c.encode(Double(position.y), forKey: .positionY)
        try c.encode(Double(fontSize), forKey: .fontSize)
        try c.encode(Double(rotationRadians), forKey: .rotationRadians)
        try c.encode(color, forKey: .color)
        try c.encode(region, forKey: .region)
        try c.encode(Double(centerOffsetX), forKey: .centerOffsetX)
        try c.encode(Double(centerOffsetY), forKey: .centerOffsetY)
        try c.encode(sequenceIndex, forKey: .sequenceIndex)
        try c.encode(isBold, forKey: .isBold)
    }
}

extension GlyphOperation: Equatable {
    nonisolated static func == (lhs: GlyphOperation, rhs: GlyphOperation) -> Bool {
        lhs.character == rhs.character &&
            lhs.position == rhs.position &&
            lhs.fontSize == rhs.fontSize &&
            lhs.rotationRadians == rhs.rotationRadians &&
            lhs.color == rhs.color &&
            lhs.region == rhs.region &&
            lhs.centerOffsetX == rhs.centerOffsetX &&
            lhs.centerOffsetY == rhs.centerOffsetY &&
            lhs.sequenceIndex == rhs.sequenceIndex &&
            lhs.isBold == rhs.isBold
    }
}
