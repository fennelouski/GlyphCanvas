//
//  GIFExportConstraintSolver.swift
//  GlyphCanvas
//

import CoreGraphics
import Foundation

enum GIFExportSliderID: Sendable, Hashable {
    case resolution
    case fps
    case frameCount
    case duration
    case fileSizeCap
    case endPercent
    case transparent
    case preset
}

enum GIFExportConstraintSolver {
    static let minFrames = 6
    static let minFps = 6
    static let minResolution = 96
    static let maxResolution = 1024
    static let maxFps = 30
    static let maxFrames = 120
    static let minEndPercent = 0.01
    static let maxEndPercent = 1.0

    /// Pixel dimensions from manifest aspect ratio and long-edge target.
    static func pixelDimensions(longEdge: Int, manifest: ArtworkManifest) -> (width: Int, height: Int) {
        let w = max(1, manifest.canvasWidth)
        let h = max(1, manifest.canvasHeight)
        let longSrc = max(w, h)
        let le = max(minResolution, min(longEdge, maxResolution))
        let s = CGFloat(le) / CGFloat(longSrc)
        let tw = max(1, Int((CGFloat(w) * s).rounded()))
        let th = max(1, Int((CGFloat(h) * s).rounded()))
        return (tw, th)
    }

    /// Heuristic encoded size for UI feedback (actual GIF may differ; encoder enforces cap).
    static func estimateBytes(
        resolution: Int,
        frameCount: Int,
        transparent: Bool,
        manifest: ArtworkManifest
    ) -> Int {
        let (tw, th) = pixelDimensions(longEdge: resolution, manifest: manifest)
        let bpp = transparent ? 0.55 : 0.45
        let body = Double(frameCount) * Double(tw * th) * bpp
        return Int(body.rounded()) + 2048
    }

    static func estimateBytes(config: GIFExportConfig, manifest: ArtworkManifest) -> Int {
        estimateBytes(
            resolution: config.resolution,
            frameCount: config.frameCount,
            transparent: config.transparentBackground,
            manifest: manifest
        )
    }

    /// When predicted size exceeds `fileSizeCapBytes`, shrink in order: frames → fps → resolution,
    /// without modifying the control the user last touched (except when only that control can move).
    static func rebalance(
        config: GIFExportConfig,
        lastChanged: GIFExportSliderID,
        manifest: ArtworkManifest
    ) -> GIFExportConfig {
        var c = clamp(config, manifest: manifest)
        let cap = max(64 * 1024, c.fileSizeCapBytes)

        /// Duration slider sets `frameCount` from target duration—protect it like a direct frame edit.
        let protectFrameCount = lastChanged == .frameCount || lastChanged == .duration

        var safety = 0
        while safety < 512 {
            safety += 1
            let est = estimateBytes(config: c, manifest: manifest)
            if est <= cap { break }

            if !protectFrameCount, c.frameCount > minFrames {
                c.frameCount -= 1
                continue
            }
            if lastChanged != .fps, c.fps > minFps {
                c.fps -= 1
                continue
            }
            if lastChanged != .resolution, c.resolution > minResolution {
                c.resolution = max(minResolution, c.resolution - 8)
                continue
            }
            // Must touch the user's slider or we're at mins: relax cap to fit (unless user just lowered cap).
            if lastChanged == .frameCount, c.frameCount > minFrames {
                c.frameCount -= 1
                continue
            }
            if lastChanged == .duration, c.frameCount > minFrames {
                c.frameCount -= 1
                continue
            }
            if lastChanged == .fps, c.fps > minFps {
                c.fps -= 1
                continue
            }
            if lastChanged == .resolution, c.resolution > minResolution {
                c.resolution = max(minResolution, c.resolution - 8)
                continue
            }
            if lastChanged != .fileSizeCap {
                c.fileSizeCapBytes = max(cap, est)
            }
            break
        }

        if let pid = c.presetID, lastChanged != .preset {
            let r = pid.recommended
            if r.resolution != c.resolution || r.fps != c.fps || r.frameCount != c.frameCount
                || r.fileSizeCapBytes != c.fileSizeCapBytes
            {
                c.presetID = nil
            }
        }

        return c
    }

    static func clamp(_ config: GIFExportConfig, manifest: ArtworkManifest) -> GIFExportConfig {
        var c = config
        c.resolution = min(maxResolution, max(minResolution, c.resolution))
        c.fps = min(maxFps, max(minFps, c.fps))
        c.frameCount = min(maxFrames, max(minFrames, c.frameCount))
        c.fileSizeCapBytes = max(256 * 1024, c.fileSizeCapBytes)
        c.endPercent = min(maxEndPercent, max(minEndPercent, c.endPercent))
        _ = manifest // reserved for future caps tied to op count
        return c
    }

    /// After duration slider: `frameCount = round(duration * fps)`.
    static func frameCount(forDuration duration: Double, fps: Int) -> Int {
        guard fps > 0, duration > 0 else { return minFrames }
        let n = Int((duration * Double(fps)).rounded())
        return min(maxFrames, max(minFrames, n))
    }
}
