//
//  GIFExportPanel.swift
//  GlyphCanvas
//

import SwiftUI

struct GIFExportPanel: View {
    let manifest: ArtworkManifest
    @Binding var config: GIFExportConfig

    private var estimatedBytes: Int {
        GIFExportConstraintSolver.estimateBytes(config: config, manifest: manifest)
    }

    private var capFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(config.fileSizeCapBytes), countStyle: .file)
    }

    private var estFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(estimatedBytes), countStyle: .file)
    }

    var body: some View {
        List {
            Section {
                Text("Source: \(manifest.canvasWidth) × \(manifest.canvasHeight) px — \(manifest.operations.count) glyphs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Preset") {
                Picker("Platform / utility", selection: Binding(
                    get: { config.presetID },
                    set: { applyPreset($0) }
                )) {
                    Text("Custom").tag(Optional<GIFExportPreset>.none)
                    ForEach(GIFExportPreset.allCases) { p in
                        Text(p.displayName).tag(Optional(p))
                    }
                }
            }

            Section("Resolution (long edge)") {
                Slider(
                    value: Binding(
                        get: { Double(config.resolution) },
                        set: { v in
                            var c = config
                            c.presetID = nil
                            c.resolution = Int((v / 8).rounded()) * 8
                            c = GIFExportConstraintSolver.rebalance(config: c, lastChanged: .resolution, manifest: manifest)
                            config = c
                        }
                    ),
                    in: Double(GIFExportConstraintSolver.minResolution)...Double(GIFExportConstraintSolver.maxResolution),
                    step: 8
                )
                let dims = GIFExportConstraintSolver.pixelDimensions(longEdge: config.resolution, manifest: manifest)
                Text("\(dims.width) × \(dims.height) px")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Section("Frame rate") {
                Slider(
                    value: Binding(
                        get: { Double(config.fps) },
                        set: { v in
                            var c = config
                            c.presetID = nil
                            c.fps = Int(v.rounded())
                            c = GIFExportConstraintSolver.rebalance(config: c, lastChanged: .fps, manifest: manifest)
                            config = c
                        }
                    ),
                    in: Double(GIFExportConstraintSolver.minFps)...Double(GIFExportConstraintSolver.maxFps),
                    step: 1
                )
                Text("\(config.fps) fps")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Section("Frames & duration") {
                Slider(
                    value: Binding(
                        get: { Double(config.frameCount) },
                        set: { v in
                            var c = config
                            c.presetID = nil
                            c.frameCount = Int(v.rounded())
                            c = GIFExportConstraintSolver.rebalance(config: c, lastChanged: .frameCount, manifest: manifest)
                            config = c
                        }
                    ),
                    in: Double(GIFExportConstraintSolver.minFrames)...Double(GIFExportConstraintSolver.maxFrames),
                    step: 1
                )
                Text("\(config.frameCount) frames — ~\(String(format: "%.2f", config.duration)) s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                let minDur = Double(GIFExportConstraintSolver.minFrames) / Double(max(config.fps, 1))
                let maxDur = Double(GIFExportConstraintSolver.maxFrames) / Double(max(config.fps, 1))
                Slider(
                    value: Binding(
                        get: { config.duration },
                        set: { newDur in
                            var c = config
                            c.presetID = nil
                            c.frameCount = GIFExportConstraintSolver.frameCount(forDuration: newDur, fps: c.fps)
                            c = GIFExportConstraintSolver.rebalance(config: c, lastChanged: .duration, manifest: manifest)
                            config = c
                        }
                    ),
                    in: minDur...maxDur
                )
                Text("Duration (adjusts frame count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("File size cap") {
                Slider(
                    value: Binding(
                        get: { Double(config.fileSizeCapBytes) },
                        set: { v in
                            var c = config
                            c.presetID = nil
                            let stepped = Int((v / Double(256 * 1024)).rounded()) * (256 * 1024)
                            c.fileSizeCapBytes = max(256 * 1024, stepped)
                            c = GIFExportConstraintSolver.rebalance(config: c, lastChanged: .fileSizeCap, manifest: manifest)
                            config = c
                        }
                    ),
                    in: Double(512 * 1024)...Double(25 * 1024 * 1024),
                    step: Double(256 * 1024)
                )
                Text("Cap: \(capFormatted)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Section("Timeline range") {
                Slider(
                    value: Binding(
                        get: { config.endPercent },
                        set: { v in
                            var c = config
                            c.presetID = nil
                            c.endPercent = v
                            c = GIFExportConstraintSolver.rebalance(config: c, lastChanged: .endPercent, manifest: manifest)
                            config = c
                        }
                    ),
                    in: GIFExportConstraintSolver.minEndPercent...GIFExportConstraintSolver.maxEndPercent
                )
                Text("Use first \(Int((config.endPercent * 100).rounded()))% of glyph timeline")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Transparent background", isOn: Binding(
                    get: { config.transparentBackground },
                    set: { on in
                        var c = config
                        c.presetID = nil
                        c.transparentBackground = on
                        c = GIFExportConstraintSolver.rebalance(config: c, lastChanged: .transparent, manifest: manifest)
                        config = c
                    }
                ))
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Estimated size: \(estFormatted)")
                        .font(.subheadline)
                    Text("Cap: \(capFormatted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func applyPreset(_ preset: GIFExportPreset?) {
        guard let preset else {
            config.presetID = nil
            return
        }
        let r = preset.recommended
        var c = config
        c.resolution = r.resolution
        c.fps = r.fps
        c.frameCount = r.frameCount
        c.fileSizeCapBytes = r.fileSizeCapBytes
        c.presetID = preset
        c = GIFExportConstraintSolver.rebalance(config: c, lastChanged: .preset, manifest: manifest)
        config = c
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        GIFExportPanel(
            manifest: ArtworkManifest(canvasWidth: 512, canvasHeight: 512, operations: []),
            config: .constant(GIFExportConfig.default())
        )
    }
}
#endif
