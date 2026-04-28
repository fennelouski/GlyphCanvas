//
//  ArtworkExport.swift
//  GlyphCanvas
//

import CoreGraphics
import Foundation

/// Resolution preset for re-rendering a saved manifest to PNG.
enum ArtworkExportResolution: String, CaseIterable, Sendable {
    case original
    case twoK
    case fourK

    nonisolated var longEdgePixels: Int? {
        switch self {
        case .original: return nil
        case .twoK: return 2048
        case .fourK: return 3840
        }
    }

    /// Short label for UI rows.
    nonisolated var presetTitle: String {
        switch self {
        case .original: return "Original"
        case .twoK: return "2K"
        case .fourK: return "4K"
        }
    }

    /// Target canvas size preserving aspect ratio; long edge matches preset (or source for original).
    nonisolated func targetSize(for manifest: ArtworkManifest) -> (width: Int, height: Int) {
        let w = max(1, manifest.canvasWidth)
        let h = max(1, manifest.canvasHeight)
        guard let long = longEdgePixels else {
            return (w, h)
        }
        let longSrc = max(w, h)
        let s = CGFloat(long) / CGFloat(longSrc)
        let tw = max(1, Int((CGFloat(w) * s).rounded()))
        let th = max(1, Int((CGFloat(h) * s).rounded()))
        return (tw, th)
    }

    /// Uniform scale from manifest canvas space to `targetSize` (long-edge driven).
    nonisolated func scaleFactor(for manifest: ArtworkManifest) -> CGFloat {
        switch self {
        case .original:
            return 1.0
        case .twoK, .fourK:
            let w = max(1, manifest.canvasWidth)
            let h = max(1, manifest.canvasHeight)
            let longSrc = max(w, h)
            let long = CGFloat(longEdgePixels!)
            return long / CGFloat(longSrc)
        }
    }
}

enum ArtworkExporter {
    /// Re-renders all operations at the requested resolution (vector text, scaled layout).
    nonisolated static func renderImage(
        manifest: ArtworkManifest,
        resolution: ArtworkExportResolution
    ) throws -> CGImage {
        let (tw, th) = resolution.targetSize(for: manifest)
        let s = resolution.scaleFactor(for: manifest)
        let ops: [GlyphOperation]
        if resolution == .original {
            ops = manifest.operations
        } else {
            ops = manifest.operations.map { scaledOperation($0, scale: s) }
        }
        return try GlyphRenderer.renderFull(
            operations: ops,
            upTo: ops.count,
            width: tw,
            height: th
        )
    }

    nonisolated static func encodePNG(_ image: CGImage) -> Data? {
        PNGExport.data(from: image)
    }

    /// Maps draw center to a zero-size `PixelRegion` + fractional offsets (avoids int drift on regions).
    nonisolated private static func scaledOperation(_ op: GlyphOperation, scale: CGFloat) -> GlyphOperation {
        let px = op.position.x * scale
        let py = op.position.y * scale
        let rx = Int(floor(px))
        let ry = Int(floor(py))
        let region = PixelRegion(x: rx, y: ry, width: 0, height: 0)
        let offX = px - (CGFloat(rx))
        let offY = py - (CGFloat(ry))
        let font = op.fontSize * scale
        return GlyphOperation(
            character: op.character,
            position: CGPoint(x: px, y: py),
            fontSize: font,
            rotationRadians: op.rotationRadians,
            color: op.color,
            region: region,
            centerOffsetX: offX,
            centerOffsetY: offY,
            sequenceIndex: op.sequenceIndex,
            isBold: op.isBold
        )
    }
}
