//
//  GIFExporter.swift
//  GlyphCanvas
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum GIFExporter {
    /// Evenly spaced timeline samples from 0 through `endPercent` of the operation count (inclusive).
    nonisolated static func sampleIndices(totalOps: Int, frameCount: Int, endPercent: Double) -> [Int] {
        guard frameCount > 0 else { return [] }
        let cap = max(0, totalOps)
        if frameCount == 1 {
            return [0]
        }
        let end = min(1.0, max(GIFExportConstraintSolver.minEndPercent, endPercent))
        var out: [Int] = []
        out.reserveCapacity(frameCount)
        for i in 0..<frameCount {
            let t = Double(i) / Double(frameCount - 1)
            let frac = t * end
            let idx = Int((frac * Double(cap)).rounded())
            out.append(min(cap, max(0, idx)))
        }
        return out
    }

    nonisolated static func targetSize(manifest: ArtworkManifest, longEdge: Int) -> (width: Int, height: Int) {
        GIFExportConstraintSolver.pixelDimensions(longEdge: longEdge, manifest: manifest)
    }

    nonisolated static func scaleFactor(manifest: ArtworkManifest, longEdge: Int) -> CGFloat {
        let w = max(1, manifest.canvasWidth)
        let h = max(1, manifest.canvasHeight)
        let longSrc = max(w, h)
        let le = CGFloat(max(GIFExportConstraintSolver.minResolution, min(longEdge, GIFExportConstraintSolver.maxResolution)))
        return le / CGFloat(longSrc)
    }

    /// Renders each sampled frame via `GlyphHistoryStore` replay.
    static func renderFrames(
        manifest: ArtworkManifest,
        config: GIFExportConfig,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [CGImage] {
        let (tw, th) = targetSize(manifest: manifest, longEdge: config.resolution)
        let s = scaleFactor(manifest: manifest, longEdge: config.resolution)
        let ops: [GlyphOperation]
        if abs(s - 1.0) < 0.000_1 {
            ops = manifest.operations
        } else {
            ops = manifest.operations.map { scaledOperation($0, scale: s) }
        }
        let totalOps = ops.count
        let indices = sampleIndices(
            totalOps: totalOps,
            frameCount: config.frameCount,
            endPercent: config.endPercent
        )
        let store = GlyphHistoryStore()
        let bg: RGBAColor = config.transparentBackground
            ? RGBAColor(r: 0, g: 0, b: 0, a: 0)
            : RGBAColor(r: 255, g: 255, b: 255, a: 255)
        try await store.importOperations(ops, width: tw, height: th, canvasBackground: bg)

        var images: [CGImage] = []
        images.reserveCapacity(indices.count)
        let total = indices.count
        for (i, idx) in indices.enumerated() {
            let img = try await store.render(upTo: idx)
            images.append(img)
            progress?(i + 1, total)
        }
        return images
    }

    /// Encodes an animated GIF. If output exceeds `capBytes`, drops every other frame (scaling delay) until under cap or at `minFrameCount`.
    /// - Parameter transparent: Matches export setting (RGBA frames already reflect transparency).
    nonisolated static func encodeGIF(
        frames: [CGImage],
        fps: Int,
        transparent: Bool,
        capBytes: Int,
        minFrameCount: Int = GIFExportConstraintSolver.minFrames
    ) -> Data? {
        _ = transparent
        guard !frames.isEmpty, fps > 0 else { return nil }
        let totalDuration = Double(frames.count) / Double(fps)
        var subset = frames
        for _ in 0..<32 {
            guard let data = encodeGIFSubset(subset, totalDuration: totalDuration) else { return nil }
            if data.count <= capBytes { return data }
            if subset.count <= minFrameCount { return data }
            subset = downsampleEveryOther(subset)
        }
        return encodeGIFSubset(subset, totalDuration: totalDuration)
    }

    nonisolated private static func downsampleEveryOther(_ frames: [CGImage]) -> [CGImage] {
        guard frames.count > 1 else { return frames }
        return stride(from: 0, to: frames.count, by: 2).map { frames[$0] }
    }

    nonisolated private static func encodeGIFSubset(_ frames: [CGImage], totalDuration: Double) -> Data? {
        let n = frames.count
        guard n > 0 else { return nil }
        let delay = max(0.02, totalDuration / Double(n))
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, n, nil) else {
            return nil
        }
        let fileProps: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0,
            ],
        ]
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)

        let frameProps: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: delay,
            ],
        ]
        for img in frames {
            CGImageDestinationAddImage(dest, img, frameProps as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    nonisolated private static func scaledOperation(_ op: GlyphOperation, scale: CGFloat) -> GlyphOperation {
        let px = op.position.x * scale
        let py = op.position.y * scale
        let rx = Int(floor(px))
        let ry = Int(floor(py))
        let region = PixelRegion(x: rx, y: ry, width: 0, height: 0)
        let offX = px - CGFloat(rx)
        let offY = py - CGFloat(ry)
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
