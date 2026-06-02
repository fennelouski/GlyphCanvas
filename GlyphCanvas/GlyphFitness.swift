//
//  GlyphFitness.swift
//  GlyphCanvas
//

import CoreGraphics
import Foundation

/// Prior glyph in the same grid cell (temporal smoothing / cell-history penalty).
struct GlyphCellPrior: Sendable {
    let stamp: String
    let fontSize: CGFloat
    let rotationDegrees: Int
}

/// Maps perceptual error (lower better) and penalties into a single loss, then **fitness** (higher better).
enum GlyphFitness {
    static let lambdaRotation: Double = 0.0015
    static let lambdaSize: Double = 0.04
    /// Mild penalty for size drift from the global average (cohesion).
    static let lambdaCohesionSize: Double = 0.02
    /// Stronger orientation penalty to keep generated words readable (favor upright text).
    static let lambdaReadabilityRotation: Double = 0.003

    /// Prefer upright glyphs (0°); penalty rises with absolute rotation.
    /// Uses quantized degrees so orientation scoring aligns with cache-key quantization.
    static func readabilityRotationPenalty(quantizedDegrees: Int) -> Double {
        let a = abs(Double(quantizedDegrees))
        return lambdaReadabilityRotation * (a * .pi / 180)
    }

    static func totalLoss(
        perceptualError: Double,
        genome: GlyphGenome,
        lastInCell: GlyphCellPrior?,
        referenceAverageFontSize: CGFloat
    ) -> Double {
        let fs = max(4, ImageProcessing.quantizedFontSize(genome.fontSize))
        let qDeg = ImageProcessing.quantizedRotationDegrees(genome.rotationRadians)
        let qRad = ImageProcessing.radians(fromQuantizedDegrees: qDeg)

        var loss = perceptualError

        if let last = lastInCell {
            let dRot = abs(qRad - CGFloat(last.rotationDegrees) * .pi / 180)
            let dSize = abs(fs - last.fontSize)
            loss += lambdaRotation * Double(dRot) + lambdaSize * Double(dSize)
        }

        let sizeDrift = abs(fs - referenceAverageFontSize)
        loss += lambdaCohesionSize * Double(sizeDrift)

        loss += readabilityRotationPenalty(quantizedDegrees: qDeg)

        return loss
    }

    /// Higher is better.
    static func fitness(
        perceptualError: Double,
        genome: GlyphGenome,
        lastInCell: GlyphCellPrior?,
        referenceAverageFontSize: CGFloat
    ) -> Double {
        -totalLoss(
            perceptualError: perceptualError,
            genome: genome,
            lastInCell: lastInCell,
            referenceAverageFontSize: referenceAverageFontSize
        )
    }
}
