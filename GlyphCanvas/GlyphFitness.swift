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
    /// Mild penalty for rotation magnitude and size drift from the global average (cohesion).
    static let lambdaCohesionRotation: Double = 0.0004
    static let lambdaCohesionSize: Double = 0.02

    /// Prefer **upright** (0°) or **quarter-turn** (±90°); mild cost for strong diagonals in between.
    /// Uses quantized degrees so preferred bearings match cache keys exactly (no `CGFloat` π slop at ±90°).
    static func readabilityRotationPenalty(quantizedDegrees: Int) -> Double {
        let a = abs(Double(quantizedDegrees))
        let distDeg = min(a, abs(a - 90))
        return lambdaCohesionRotation * (distDeg * .pi / 180)
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
