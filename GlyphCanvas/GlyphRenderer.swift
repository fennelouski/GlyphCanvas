//
//  GlyphRenderer.swift
//  GlyphCanvas
//

import CoreGraphics
import Foundation

/// Renders a prefix of glyph operations onto a canvas (shared by live engine semantics and history replay).
enum GlyphRenderer {
    /// Renders `operations[0..<index]` onto a fresh canvas filled with `canvasBackground`. `index` is clamped to `0...operations.count`.
    nonisolated static func render(
        operations: [GlyphOperation],
        upTo index: Int,
        width: Int,
        height: Int,
        startingCheckpointPrefixLength: Int,
        checkpointImage: CGImage?,
        canvasBackground: RGBAColor = RGBAColor(r: 255, g: 255, b: 255, a: 255)
    ) throws -> CGImage {
        let clamped = max(0, min(index, operations.count))
        let start = max(0, min(startingCheckpointPrefixLength, clamped))

        let canvasBuffer = PixelBuffer(width: width, height: height)
        guard let context = ImageProcessing.makeContext(width: width, height: height, data: canvasBuffer.data) else {
            throw ImageProcessingError.contextFailure
        }

        if start == 0 {
            context.setFillColor(canvasBackground.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        } else if let checkpointImage {
            context.setFillColor(canvasBackground.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .none
            context.draw(checkpointImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        } else {
            context.setFillColor(canvasBackground.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }

        if start < clamped {
            for i in start..<clamped {
                ImageProcessing.drawGlyph(operations[i].makeCandidate(), in: context)
            }
        }

        guard let image = context.makeImage() else {
            throw ImageProcessingError.contextFailure
        }
        return image
    }

    /// Full replay with no checkpoint (for tests and fallback).
    nonisolated static func renderFull(
        operations: [GlyphOperation],
        upTo index: Int,
        width: Int,
        height: Int,
        canvasBackground: RGBAColor = RGBAColor(r: 255, g: 255, b: 255, a: 255)
    ) throws -> CGImage {
        try render(
            operations: operations,
            upTo: index,
            width: width,
            height: height,
            startingCheckpointPrefixLength: 0,
            checkpointImage: nil,
            canvasBackground: canvasBackground
        )
    }
}
