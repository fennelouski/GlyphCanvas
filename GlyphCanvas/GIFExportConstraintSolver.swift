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
    case aspect
    case preset
}

/// Output frame geometry: the pixel canvas to render into, plus the uniform scale and
/// centering translation that map source-canvas glyph coordinates into that frame.
/// For `.source` aspect the offsets are zero; for fixed ratios (portrait 9:16) the artwork is
/// fit-inside and centered, leaving background-filled letterbox / pillarbox bars.
struct GIFRenderGeometry: Sendable, Hashable {
    var width: Int
    var height: Int
    var scale: CGFloat
    var offsetX: CGFloat
    var offsetY: CGFloat
}

enum GIFExportConstraintSolver {
    nonisolated static let minFrames = 6
    nonisolated static let minFps = 6
    nonisolated static let minResolution = 96
    nonisolated static let maxResolution = 1024
    nonisolated static let maxFps = 30
    nonisolated static let maxFrames = 120
    nonisolated static let minEndPercent = 0.01
    nonisolated static let maxEndPercent = 1.0

    /// Pixel dimensions from manifest aspect ratio and long-edge target.
    nonisolated static func pixelDimensions(longEdge: Int, manifest: ArtworkManifest) -> (width: Int, height: Int) {
        let w = max(1, manifest.canvasWidth)
        let h = max(1, manifest.canvasHeight)
        let longSrc = max(w, h)
        let le = max(minResolution, min(longEdge, maxResolution))
        let s = CGFloat(le) / CGFloat(longSrc)
        let tw = max(1, Int((CGFloat(w) * s).rounded()))
        let th = max(1, Int((CGFloat(h) * s).rounded()))
        return (tw, th)
    }

    /// Full output geometry for a config, honoring `config.aspect`.
    /// `.source` keeps the artwork's aspect ratio; a fixed ratio (portrait 9:16) fits the artwork
    /// inside a ratio-shaped frame, centered, so the encoder's background fills the letterbox bars.
    nonisolated static func renderGeometry(config: GIFExportConfig, manifest: ArtworkManifest) -> GIFRenderGeometry {
        let srcW = CGFloat(max(1, manifest.canvasWidth))
        let srcH = CGFloat(max(1, manifest.canvasHeight))
        let le = CGFloat(max(minResolution, min(config.resolution, maxResolution)))

        guard let ratio = config.aspect.ratio else {
            // Match artwork: uniform long-edge scale, no letterboxing.
            let longSrc = max(srcW, srcH)
            let s = le / longSrc
            let tw = max(1, Int((srcW * s).rounded()))
            let th = max(1, Int((srcH * s).rounded()))
            return GIFRenderGeometry(width: tw, height: th, scale: s, offsetX: 0, offsetY: 0)
        }

        // Fixed ratio. `resolution` (long edge) drives the taller edge for portrait, else the wider.
        let rw = CGFloat(max(1, ratio.w))
        let rh = CGFloat(max(1, ratio.h))
        let frameW: CGFloat
        let frameH: CGFloat
        if rh >= rw {
            frameH = le
            frameW = (le * rw / rh).rounded()
        } else {
            frameW = le
            frameH = (le * rh / rw).rounded()
        }
        let fw = max(1, frameW)
        let fh = max(1, frameH)
        // Fit-inside so the whole artwork is visible; center it, leaving background bars.
        let fit = min(fw / srcW, fh / srcH)
        let contentW = srcW * fit
        let contentH = srcH * fit
        let dx = (fw - contentW) / 2
        let dy = (fh - contentH) / 2
        return GIFRenderGeometry(
            width: max(1, Int(fw.rounded())),
            height: max(1, Int(fh.rounded())),
            scale: fit,
            offsetX: dx,
            offsetY: dy
        )
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
        // Use the true output frame (which may be letterboxed to a fixed aspect), not the source aspect.
        let g = renderGeometry(config: config, manifest: manifest)
        let bpp = config.transparentBackground ? 0.55 : 0.45
        let body = Double(config.frameCount) * Double(g.width * g.height) * bpp
        return Int(body.rounded()) + 2048
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
                || r.fileSizeCapBytes != c.fileSizeCapBytes || r.aspect != c.aspect
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
