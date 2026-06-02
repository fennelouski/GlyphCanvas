//
//  GIFExportConfig.swift
//  GlyphCanvas
//

import CryptoKit
import Foundation

/// User-tunable GIF export parameters. `presetID` is nil or `.custom` when the user has diverged from a named preset.
struct GIFExportConfig: Sendable, Hashable, Codable {
    nonisolated static let encoderFormatVersion = 1

    /// Long-edge pixel target (after aspect-preserving scale).
    var resolution: Int
    var fps: Int
    var frameCount: Int
    var fileSizeCapBytes: Int
    /// Fraction of the full operation timeline to include, from 0% up to this value (0.01…1.0).
    var endPercent: Double
    var transparentBackground: Bool
    /// When user picks a platform preset; `nil` means treat as custom / legacy.
    var presetID: GIFExportPreset?

    var duration: Double {
        guard fps > 0 else { return 0 }
        return Double(frameCount) / Double(fps)
    }

    static func `default`() -> GIFExportConfig {
        let p = GIFExportPreset.webEmbed.recommended
        return GIFExportConfig(
            resolution: p.resolution,
            fps: p.fps,
            frameCount: p.frameCount,
            fileSizeCapBytes: p.fileSizeCapBytes,
            endPercent: 1.0,
            transparentBackground: false,
            presetID: .webEmbed
        )
    }

    /// Stable manifest fingerprint for cache invalidation when operations change.
    nonisolated func manifestFingerprint(_ manifest: ArtworkManifest) -> String {
        let lastSeq = manifest.operations.last.map { String($0.sequenceIndex) } ?? ""
        return "\(manifest.id.uuidString)|\(manifest.canvasWidth)|\(manifest.canvasHeight)|\(manifest.operations.count)|\(lastSeq)"
    }

    /// SHA-256 hex used as the on-disk cache file basename (plus `.gif` / `.json`).
    nonisolated func cacheKeyHash(manifest: ArtworkManifest) -> String {
        let presetRaw = presetID?.rawValue ?? "custom"
        let payload = [
            "\(Self.encoderFormatVersion)",
            manifestFingerprint(manifest),
            "\(resolution)",
            "\(fps)",
            "\(frameCount)",
            "\(fileSizeCapBytes)",
            String(format: "%.6f", endPercent),
            transparentBackground ? "1" : "0",
            presetRaw,
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
