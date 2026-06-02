//
//  GlyphGenome.swift
//  GlyphCanvas
//

import CoreGraphics
import Foundation
import simd

/// Evolvable glyph parameters for a single region. Higher-level fitness is computed externally.
struct GlyphGenome: Sendable {
    /// Keep glyphs near upright orientation for word legibility.
    private static let maxReadableRotationRadians: CGFloat = .pi / 6

    /// Single stamp: one character, one emoji, or one word.
    var stamp: String
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
            character: stamp,
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
        colorQuantizationStep: Int = 1,
        stampPool: [String],
        isBold: Bool,
        rng: inout some RandomNumberGenerator
    ) -> GlyphGenome {
        let ch = ImageProcessing.randomCoverageAwareStamp(meanLuminanceY: meanLuminanceY, stampPool: stampPool)
        var fs = averageFontSize + CGFloat.random(in: -2...2, using: &rng)
        fs = max(4, fs)
        let rot = CGFloat.random(in: (-maxReadableRotationRadians)...(maxReadableRotationRadians), using: &rng)
        let jitterMax = max(1, min(region.width, region.height) / 4)
        let ox = CGFloat.random(in: -CGFloat(jitterMax)...CGFloat(jitterMax), using: &rng)
        let oy = CGFloat.random(in: -CGFloat(jitterMax)...CGFloat(jitterMax), using: &rng)
        let r = baseRGB.x + Float.random(in: -18...18, using: &rng)
        let g = baseRGB.y + Float.random(in: -18...18, using: &rng)
        let b = baseRGB.z + Float.random(in: -18...18, using: &rng)
        let qr = ImageProcessing.quantizeChannel(UInt8(min(255, max(0, r)).rounded()), step: colorQuantizationStep)
        let qg = ImageProcessing.quantizeChannel(UInt8(min(255, max(0, g)).rounded()), step: colorQuantizationStep)
        let qb = ImageProcessing.quantizeChannel(UInt8(min(255, max(0, b)).rounded()), step: colorQuantizationStep)
        return GlyphGenome(
            stamp: ch,
            fontSize: fs,
            rotationRadians: clampedReadableRotation(rot),
            colorR: Float(qr),
            colorG: Float(qg),
            colorB: Float(qb),
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
        colorQuantizationStep: Int = 1,
        stampPool: [String],
        stampIsBold: Bool,
        rng: inout some RandomNumberGenerator
    ) {
        if Double.random(in: 0..<1, using: &rng) < 0.05 {
            stamp = ImageProcessing.randomCoverageAwareStamp(meanLuminanceY: meanLuminanceY, stampPool: stampPool)
        }

        let dSize = CGFloat.random(in: -2...2, using: &rng)
        fontSize = max(4, ImageProcessing.quantizedFontSize(fontSize + dSize))

        let dRot = CGFloat.random(in: -0.35...0.35, using: &rng)
        rotationRadians = Self.clampedReadableRotation(rotationRadians + dRot)

        colorR = min(255, max(0, colorR + Float.random(in: -22...22, using: &rng)))
        colorG = min(255, max(0, colorG + Float.random(in: -22...22, using: &rng)))
        colorB = min(255, max(0, colorB + Float.random(in: -22...22, using: &rng)))
        colorR = Float(ImageProcessing.quantizeChannel(UInt8(colorR.rounded()), step: colorQuantizationStep))
        colorG = Float(ImageProcessing.quantizeChannel(UInt8(colorG.rounded()), step: colorQuantizationStep))
        colorB = Float(ImageProcessing.quantizeChannel(UInt8(colorB.rounded()), step: colorQuantizationStep))

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
                colorQuantizationStep: colorQuantizationStep,
                stampPool: stampPool,
                isBold: stampIsBold,
                rng: &rng
            )
        }
    }

    static func crossover(
        _ a: GlyphGenome,
        _ b: GlyphGenome,
        colorQuantizationStep: Int = 1,
        rng: inout some RandomNumberGenerator
    ) -> GlyphGenome {
        let stampParent = Bool.random(using: &rng) ? a : b
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
        let qr = ImageProcessing.quantizeChannel(UInt8(min(255, max(0, r)).rounded()), step: colorQuantizationStep)
        let qg = ImageProcessing.quantizeChannel(UInt8(min(255, max(0, g)).rounded()), step: colorQuantizationStep)
        let qb = ImageProcessing.quantizeChannel(UInt8(min(255, max(0, bl)).rounded()), step: colorQuantizationStep)
        let clampedRot = clampedReadableRotation(rot)
        return GlyphGenome(
            stamp: stampParent.stamp,
            fontSize: sizeParent.fontSize,
            rotationRadians: clampedRot,
            colorR: Float(qr),
            colorG: Float(qg),
            colorB: Float(qb),
            offsetX: ox,
            offsetY: oy,
            isBold: Bool.random(using: &rng) ? a.isBold : b.isBold
        )
    }

    private static func clampedReadableRotation(_ radians: CGFloat) -> CGFloat {
        max(-maxReadableRotationRadians, min(maxReadableRotationRadians, radians))
    }
}

extension GlyphGenome: Equatable {
    nonisolated static func == (lhs: GlyphGenome, rhs: GlyphGenome) -> Bool {
        lhs.stamp == rhs.stamp &&
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
