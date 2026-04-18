//
//  GlyphGenome.swift
//  GlyphCanvas
//

import CoreGraphics
import Foundation
import simd

/// Evolvable glyph parameters for a single region. Higher-level fitness is computed externally.
struct GlyphGenome: Sendable {
    var character: Character
    var fontSize: CGFloat
    var rotationRadians: CGFloat
    /// RGB 0…255
    var colorR: Float
    var colorG: Float
    var colorB: Float
    /// Jitter from region center in pixels (scratch space).
    var offsetX: CGFloat
    var offsetY: CGFloat
    /// Matches the current stamp’s bold coin flip (not mutated by GA).
    var isBold: Bool

    func rgbaColor(alpha: Float = 255) -> RGBAColor {
        ImageProcessing.rgbaColor(
            from: SIMD3<Float>(colorR, colorG, colorB),
            alpha: alpha
        )
    }

    func toCandidate(region: PixelRegion) -> GlyphCandidate {
        let fs = max(4, ImageProcessing.quantizedFontSize(fontSize))
        let qDeg = ImageProcessing.quantizedRotationDegrees(rotationRadians)
        let qRad = ImageProcessing.radians(fromQuantizedDegrees: qDeg)
        return GlyphCandidate(
            character: String(character),
            fontSize: fs,
            rotationRadians: qRad,
            color: rgbaColor(),
            region: region,
            centerOffsetX: offsetX,
            centerOffsetY: offsetY,
            isBold: isBold
        )
    }

    // MARK: - Factory

    static func random(
        region: PixelRegion,
        meanLuminanceY: Double,
        averageFontSize: CGFloat,
        baseRGB: SIMD3<Float>,
        characterPool: [Character],
        isBold: Bool,
        rng: inout some RandomNumberGenerator
    ) -> GlyphGenome {
        let ch = ImageProcessing.randomCoverageAwareCharacter(meanLuminanceY: meanLuminanceY, characterPool: characterPool)
        var fs = averageFontSize + CGFloat.random(in: -2...2, using: &rng)
        fs = max(4, fs)
        let rot = CGFloat.random(in: (-.pi / 2)...(.pi / 2), using: &rng)
        let jitterMax = max(1, min(region.width, region.height) / 4)
        let ox = CGFloat.random(in: -CGFloat(jitterMax)...CGFloat(jitterMax), using: &rng)
        let oy = CGFloat.random(in: -CGFloat(jitterMax)...CGFloat(jitterMax), using: &rng)
        let r = baseRGB.x + Float.random(in: -18...18, using: &rng)
        let g = baseRGB.y + Float.random(in: -18...18, using: &rng)
        let b = baseRGB.z + Float.random(in: -18...18, using: &rng)
        return GlyphGenome(
            character: ch,
            fontSize: fs,
            rotationRadians: rot,
            colorR: min(255, max(0, r)),
            colorG: min(255, max(0, g)),
            colorB: min(255, max(0, b)),
            offsetX: ox,
            offsetY: oy,
            isBold: isBold
        )
    }

    /// Controlled mutation; keeps traits near the parent unless `hardReset` triggers exploration.
    mutating func mutate(
        region: PixelRegion,
        meanLuminanceY: Double,
        averageFontSize: CGFloat,
        baseRGB: SIMD3<Float>,
        characterPool: [Character],
        stampIsBold: Bool,
        rng: inout some RandomNumberGenerator
    ) {
        if Double.random(in: 0..<1, using: &rng) < 0.05 {
            character = ImageProcessing.randomCoverageAwareCharacter(meanLuminanceY: meanLuminanceY, characterPool: characterPool)
        }

        let dSize = CGFloat.random(in: -2...2, using: &rng)
        fontSize = max(4, ImageProcessing.quantizedFontSize(fontSize + dSize))

        let dRot = CGFloat.random(in: -0.35...0.35, using: &rng)
        rotationRadians += dRot
        rotationRadians = max(-(.pi / 2 + 0.2), min(.pi / 2 + 0.2, rotationRadians))

        colorR = min(255, max(0, colorR + Float.random(in: -22...22, using: &rng)))
        colorG = min(255, max(0, colorG + Float.random(in: -22...22, using: &rng)))
        colorB = min(255, max(0, colorB + Float.random(in: -22...22, using: &rng)))

        let jitterMax = max(1, min(region.width, region.height) / 4)
        offsetX += CGFloat.random(in: -1.5...1.5, using: &rng)
        offsetY += CGFloat.random(in: -1.5...1.5, using: &rng)
        offsetX = max(-CGFloat(jitterMax), min(CGFloat(jitterMax), offsetX))
        offsetY = max(-CGFloat(jitterMax), min(CGFloat(jitterMax), offsetY))

        if Double.random(in: 0..<1, using: &rng) < 0.015 {
            self = GlyphGenome.random(
                region: region,
                meanLuminanceY: meanLuminanceY,
                averageFontSize: averageFontSize,
                baseRGB: baseRGB,
                characterPool: characterPool,
                isBold: stampIsBold,
                rng: &rng
            )
        }
    }

    static func crossover(
        _ a: GlyphGenome,
        _ b: GlyphGenome,
        rng: inout some RandomNumberGenerator
    ) -> GlyphGenome {
        let charParent = Bool.random(using: &rng) ? a : b
        let sizeParent = Bool.random(using: &rng) ? a : b
        let rot: CGFloat
        if Bool.random(using: &rng) {
            rot = Bool.random(using: &rng) ? a.rotationRadians : b.rotationRadians
        } else {
            rot = (a.rotationRadians + b.rotationRadians) / 2 + CGFloat.random(in: -0.08...0.08, using: &rng)
        }
        let t = Double.random(in: 0.35...0.65, using: &rng)
        let r = Float(t) * a.colorR + Float(1 - t) * b.colorR
        let g = Float(t) * a.colorG + Float(1 - t) * b.colorG
        let bl = Float(t) * a.colorB + Float(1 - t) * b.colorB
        let ox = (a.offsetX + b.offsetX) / 2 + CGFloat.random(in: -0.75...0.75, using: &rng)
        let oy = (a.offsetY + b.offsetY) / 2 + CGFloat.random(in: -0.75...0.75, using: &rng)
        return GlyphGenome(
            character: charParent.character,
            fontSize: sizeParent.fontSize,
            rotationRadians: rot,
            colorR: min(255, max(0, r)),
            colorG: min(255, max(0, g)),
            colorB: min(255, max(0, bl)),
            offsetX: ox,
            offsetY: oy,
            isBold: Bool.random(using: &rng) ? a.isBold : b.isBold
        )
    }
}

extension GlyphGenome: Equatable {
    nonisolated static func == (lhs: GlyphGenome, rhs: GlyphGenome) -> Bool {
        lhs.character == rhs.character &&
            lhs.fontSize == rhs.fontSize &&
            lhs.rotationRadians == rhs.rotationRadians &&
            lhs.colorR == rhs.colorR &&
            lhs.colorG == rhs.colorG &&
            lhs.colorB == rhs.colorB &&
            lhs.offsetX == rhs.offsetX &&
            lhs.offsetY == rhs.offsetY &&
            lhs.isBold == rhs.isBold
    }
}
