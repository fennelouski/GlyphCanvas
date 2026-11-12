//
//  VideoTransitionComposer.swift
//  GlyphCanvas
//
//  Builds the AVComposition (video, audio crossfade) for a TransitionEdit, plus the custom
//  compositor that draws the glyph build over clip 1. Preview and export share this path.
//

import AVFoundation
import CoreGraphics
import CoreImage
import ImageIO

/// Glyphs that rebuild clip 2's first frame, in `size` (plan) pixel space, top-left origin.
nonisolated final class GlyphPlan: @unchecked Sendable {
    let ops: [GlyphOperation]
    let size: CGSize

    init(ops: [GlyphOperation], size: CGSize) {
        self.ops = ops
        self.size = size
    }

    static let empty = GlyphPlan(ops: [], size: CGSize(width: 1, height: 1))
}

nonisolated struct TransitionRenderConfig: @unchecked Sendable {
    let track1: CMPersistentTrackID
    let track2: CMPersistentTrackID
    let orientation1: CGImagePropertyOrientation
    let orientation2: CGImagePropertyOrientation
    let renderSize: CGSize
    let transitionStart: Double
    let cut: Double
    let style: GlyphRevealStyle
    let plan: GlyphPlan

    /// Glyph layer fades off clip 2 over this long after the cut.
    static let dissolve = 0.35
}

nonisolated final class GlyphTransitionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let config: TransitionRenderConfig

    init(timeRange: CMTimeRange, sourceTrack: CMPersistentTrackID, config: TransitionRenderConfig) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = [NSNumber(value: sourceTrack)]
        self.config = config
    }
}

// MARK: - Compositor

nonisolated final class GlyphTransitionCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    /// ponytail: animated (non-committed) glyphs drawn per frame are capped; the rest snap into the committed layer.
    private static let maxInFlight = 150

    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    /// Committed glyphs at render size, reused across frames while time moves forward.
    private var layer: CGContext?
    private var layerKey: (plan: ObjectIdentifier, size: CGSize)?
    private var layerCount = 0

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
    func cancelAllPendingVideoCompositionRequests() {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? GlyphTransitionInstruction,
              let out = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "GlyphTransition", code: 1))
            return
        }
        lock.lock()
        defer { lock.unlock() }
        autoreleasepool {
            render(request, config: instruction.config, into: out)
        }
        request.finish(withComposedVideoFrame: out)
    }

    private func render(_ request: AVAsynchronousVideoCompositionRequest, config c: TransitionRenderConfig, into out: CVPixelBuffer) {
        let t = request.compositionTime.seconds
        let afterCut = t >= c.cut
        if let src = request.sourceFrame(byTrackID: afterCut ? c.track2 : c.track1) {
            let image = CIImage(cvPixelBuffer: src).oriented(afterCut ? c.orientation2 : c.orientation1)
            ciContext.render(Self.aspectFill(image, into: c.renderSize), to: out)
        }

        let ops = c.plan.ops
        let layerAlpha = afterCut ? 1 - (t - c.cut) / TransitionRenderConfig.dissolve : 1
        guard !ops.isEmpty, t >= c.transitionStart, layerAlpha > 0 else { return }

        let total = ops.count
        let revealed = min(total, Int(GlyphTransitionPacing.revealed(at: t, total: total, start: c.transitionStart, cut: c.cut)))
        let settled = Int(GlyphTransitionPacing.revealed(at: t - c.style.maxDuration, total: total, start: c.transitionStart, cut: c.cut))
        let committed = min(revealed, max(settled, revealed - Self.maxInFlight))

        let w = Int(c.renderSize.width), h = Int(c.renderSize.height)
        guard let layer = committedLayer(plan: c.plan, size: c.renderSize, count: committed) else { return }

        CVPixelBufferLockBaseAddress(out, [])
        defer { CVPixelBufferUnlockBaseAddress(out, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(out),
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(out),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        ctx.setAlpha(layerAlpha)
        if let image = layer.makeImage() {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        // In-flight glyphs, in plan space (top-left origin) like the engine's canvas.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        let k = c.renderSize.width / c.plan.size.width
        ctx.scaleBy(x: k, y: k)
        for i in committed..<revealed {
            let op = ops[i]
            let style = c.style.resolved(for: op.sequenceIndex)
            let birth = GlyphTransitionPacing.birth(of: i, total: total, start: c.transitionStart, cut: c.cut)
            let pose = GlyphRevealMath.pose(
                style,
                t: (t - birth) / style.duration,
                seed: UInt64(truncatingIfNeeded: op.sequenceIndex),
                fadeOut: false
            )
            let fs = op.fontSize
            ctx.saveGState()
            ctx.setAlpha(layerAlpha * pose.opacity)
            ctx.translateBy(x: op.position.x + pose.offset.width * fs, y: op.position.y + pose.offset.height * fs)
            ctx.rotate(by: pose.rotation)
            ctx.scaleBy(x: pose.scale, y: pose.scale * pose.scaleY)
            ctx.translateBy(x: -op.position.x, y: -op.position.y)
            ImageProcessing.drawGlyph(op.makeCandidate(), in: ctx)
            ctx.restoreGState()
        }
    }

    private func committedLayer(plan: GlyphPlan, size: CGSize, count: Int) -> CGContext? {
        let key = (plan: ObjectIdentifier(plan), size: size)
        if layer == nil || layerKey?.plan != key.plan || layerKey?.size != key.size {
            layer = ImageProcessing.makeContext(width: Int(size.width), height: Int(size.height), data: nil)
            layerKey = key
            layerCount = 0
        }
        guard let layer else { return nil }
        if count < layerCount {
            // Scrubbed backwards: rebuild from scratch.
            layer.clear(CGRect(origin: .zero, size: size))
            layerCount = 0
        }
        if count > layerCount {
            let k = size.width / plan.size.width
            layer.saveGState()
            layer.scaleBy(x: k, y: k)
            for op in plan.ops[layerCount..<count] {
                ImageProcessing.drawGlyph(op.makeCandidate(), in: layer)
            }
            layer.restoreGState()
            layerCount = count
        }
        return layer
    }

    static func aspectFill(_ image: CIImage, into size: CGSize) -> CIImage {
        let e = image.extent
        let s = max(size.width / e.width, size.height / e.height)
        let transform = CGAffineTransform(translationX: -e.minX, y: -e.minY)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: (size.width - e.width * s) / 2, y: (size.height - e.height * s) / 2))
        return image.transformed(by: transform).cropped(to: CGRect(origin: .zero, size: size))
    }
}

// MARK: - Composition

nonisolated struct TransitionSource: @unchecked Sendable {
    let url: URL
    let asset: AVURLAsset
    let video: AVAssetTrack
    let audio: AVAssetTrack?
    let audioDuration: Double
    let orientation: CGImagePropertyOrientation
    /// Upright display size.
    let displaySize: CGSize
    let frameRate: Float
    let duration: Double

    static func load(_ url: URL) async throws -> TransitionSource {
        let asset = AVURLAsset(url: url)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "GlyphTransition", code: 2, userInfo: [NSLocalizedDescriptionKey: "That file has no video track."])
        }
        let (natural, transform, fps) = try await video.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let audioDuration = try await audio?.load(.timeRange).end.seconds ?? 0
        let duration = try await asset.load(.duration).seconds
        let orientation = orientation(for: transform)
        let rotated = orientation == .left || orientation == .right
        return TransitionSource(
            url: url,
            asset: asset,
            video: video,
            audio: audio,
            audioDuration: audioDuration,
            orientation: orientation,
            displaySize: rotated ? CGSize(width: natural.height, height: natural.width) : natural,
            frameRate: fps,
            duration: duration
        )
    }

    static func orientation(for t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a, t.b, t.c, t.d) {
        case (0, 1, -1, 0): .right
        case (0, -1, 1, 0): .left
        case (-1, 0, 0, -1): .down
        default: .up
        }
    }

    /// Even dimensions (encoders require it).
    var renderSize: CGSize {
        CGSize(width: max(2, (Int(displaySize.width) / 2) * 2), height: max(2, (Int(displaySize.height) / 2) * 2))
    }
}

nonisolated struct TransitionComposition: @unchecked Sendable {
    let composition: AVComposition
    let videoComposition: AVVideoComposition
    let audioMix: AVAudioMix
}

nonisolated enum TransitionComposer {
    static func cm(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

    static func build(edit e: TransitionEdit, clip1: TransitionSource, clip2: TransitionSource, style: GlyphRevealStyle, plan: GlyphPlan) throws -> TransitionComposition {
        let comp = AVMutableComposition()
        guard let v1 = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let v2 = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "GlyphTransition", code: 3)
        }
        try v1.insertTimeRange(CMTimeRange(start: cm(e.clip1In), duration: cm(e.cut)), of: clip1.video, at: .zero)
        try v2.insertTimeRange(CMTimeRange(start: cm(e.clip2In), duration: cm(e.clip2Length)), of: clip2.video, at: cm(e.cut))

        var mixParams: [AVMutableAudioMixInputParameters] = []
        if let a1 = clip1.audio, e.clip1In < clip1.audioDuration,
           let t1 = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let length = min(e.cut + e.clip1AudioTail, clip1.audioDuration - e.clip1In)
            try t1.insertTimeRange(CMTimeRange(start: cm(e.clip1In), duration: cm(length)), of: a1, at: .zero)
            let p = AVMutableAudioMixInputParameters(track: t1)
            p.setVolume(e.clip1Volume, at: .zero)
            if e.clip1AudioTail > 0 {
                p.setVolumeRamp(fromStartVolume: e.clip1Volume, toEndVolume: 0, timeRange: CMTimeRange(start: cm(e.cut), duration: cm(e.clip1AudioTail)))
            }
            mixParams.append(p)
        }
        if let a2 = clip2.audio, e.clip2In < clip2.audioDuration,
           let t2 = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let length = min(e.clip2Length, clip2.audioDuration - e.clip2In)
            try t2.insertTimeRange(CMTimeRange(start: cm(e.clip2In), duration: cm(length)), of: a2, at: cm(e.cut))
            let p = AVMutableAudioMixInputParameters(track: t2)
            if e.clip2FadeIn > 0 {
                p.setVolume(0, at: .zero)
                p.setVolumeRamp(fromStartVolume: 0, toEndVolume: e.clip2Volume, timeRange: CMTimeRange(start: cm(e.cut), duration: cm(e.clip2FadeIn)))
            } else {
                p.setVolume(e.clip2Volume, at: .zero)
            }
            mixParams.append(p)
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = mixParams

        let config = TransitionRenderConfig(
            track1: v1.trackID,
            track2: v2.trackID,
            orientation1: clip1.orientation,
            orientation2: clip2.orientation,
            renderSize: clip1.renderSize,
            transitionStart: e.transitionStart,
            cut: e.cut,
            style: style,
            plan: plan
        )
        let vc = AVMutableVideoComposition()
        vc.customVideoCompositorClass = GlyphTransitionCompositor.self
        vc.renderSize = clip1.renderSize
        let fps = clip1.frameRate > 1 ? min(60, clip1.frameRate.rounded()) : 30
        vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        vc.instructions = [
            GlyphTransitionInstruction(timeRange: CMTimeRange(start: .zero, end: cm(e.cut)), sourceTrack: v1.trackID, config: config),
            GlyphTransitionInstruction(timeRange: CMTimeRange(start: cm(e.cut), end: max(comp.duration, cm(e.outputDuration))), sourceTrack: v2.trackID, config: config)
        ]
        return TransitionComposition(composition: comp, videoComposition: vc, audioMix: mix)
    }

    /// Clip 2's frame at `seconds`, aspect-filled to clip 1's shape at ≤512 px (the glyph engine's working size).
    static func planningFrame(of clip: TransitionSource, at seconds: Double, renderSize: CGSize) async throws -> CGImage {
        let gen = AVAssetImageGenerator(asset: clip.asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        let (frame, _) = try await gen.image(at: cm(seconds))

        let scale = 512 / max(renderSize.width, renderSize.height)
        let pw = max(16, Int((renderSize.width * scale).rounded()))
        let ph = max(16, Int((renderSize.height * scale).rounded()))
        guard let ctx = CGContext(
            data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ImageProcessingError.contextFailure }
        let s = max(CGFloat(pw) / CGFloat(frame.width), CGFloat(ph) / CGFloat(frame.height))
        let fw = CGFloat(frame.width) * s, fh = CGFloat(frame.height) * s
        ctx.interpolationQuality = .high
        ctx.draw(frame, in: CGRect(x: (CGFloat(pw) - fw) / 2, y: (CGFloat(ph) - fh) / 2, width: fw, height: fh))
        guard let image = ctx.makeImage() else { throw ImageProcessingError.contextFailure }
        return image
    }

    /// Fraction of pixels with visible glyph ink (sampled).
    static func alphaCoverage(_ ctx: CGContext) -> Double {
        guard let data = ctx.data else { return 0 }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let stride = 3
        var hit = 0, total = 0
        for y in Swift.stride(from: 0, to: ctx.height, by: stride) {
            let row = bytes + y * ctx.bytesPerRow
            for x in Swift.stride(from: 0, to: ctx.width, by: stride) {
                total += 1
                if row[x * 4 + 3] > 96 { hit += 1 }
            }
        }
        return total == 0 ? 0 : Double(hit) / Double(total)
    }
}

extension TransitionComposer {
    /// Runs the glyph engine on `frame` until glyphs cover `coverage` of it. Main actor (the engine is), yielding often.
    @MainActor
    static func makePlan(frame: CGImage, coverage: Double, progress: (Double) -> Void) async throws -> GlyphPlan {
        let background = (try? ImageProcessing.darkestAmongTopFiveCommonColors(from: frame)) ?? RGBAColor(r: 255, g: 255, b: 255, a: 255)
        let engine = try GlyphRenderEngine(target: frame, canvasBackground: background)
        guard let ink = ImageProcessing.makeContext(width: frame.width, height: frame.height, data: nil) else {
            throw ImageProcessingError.contextFailure
        }
        let defaults = UserDefaults.standard
        let stamps = StampSetPipeline.activeSet(
            base: defaults.string(forKey: GlyphCanvasStorageKey.baseCharacterSet) ?? GlyphCanvasCharacterSetDefaults.baseString,
            mode: CharacterCaseMode(rawValue: defaults.string(forKey: GlyphCanvasStorageKey.characterCaseMode) ?? "") ?? .both,
            source: StampSourceMode(rawValue: defaults.string(forKey: GlyphCanvasStorageKey.stampSourceMode) ?? "") ?? .characters
        )

        var ops: [GlyphOperation] = []
        var iterations = 0
        // ponytail: fixed caps keep planning to a few seconds; raise if users want denser mosaics.
        while iterations < 30_000, ops.count < 5_000 {
            try Task.checkCancellation()
            let metrics = engine.performIteration(
                mode: .greedy,
                encodingComparisonMode: .perceptual,
                colorFidelity: 8,
                regionSize: 12,
                greedyCandidateCount: 6,
                geneticConfig: .default,
                averageFontSize: 12,
                stampPool: stamps
            )
            iterations += 1
            if let op = metrics.committedOperation {
                ops.append(op)
                ImageProcessing.drawGlyph(op.makeCandidate(), in: ink)
                if ops.count % 25 == 0 {
                    let covered = alphaCoverage(ink)
                    progress(min(1, covered / coverage))
                    if ops.count >= 300, covered >= coverage { break }
                }
            }
            if iterations % 8 == 0 { try await Task.sleep(for: .milliseconds(1)) }
        }
        return GlyphPlan(ops: ops, size: CGSize(width: frame.width, height: frame.height))
    }
}

// MARK: - Timeline media (thumbnails + waveform)

nonisolated struct ClipMedia: @unchecked Sendable {
    var thumbnails: [CGImage] = []
    var thumbnailInterval: Double = 1
    var aspect: CGFloat = 16 / 9
    /// Peak amplitude 0...1, `peaksPerSecond` per second of source.
    var peaks: [Float] = []
    static let peaksPerSecond = 50

    static func load(_ source: TransitionSource) async -> ClipMedia {
        async let thumbs = thumbnails(source)
        async let peaks = waveform(source.url)
        let (images, interval) = await thumbs
        return ClipMedia(
            thumbnails: images,
            thumbnailInterval: interval,
            aspect: source.displaySize.width / max(1, source.displaySize.height),
            peaks: await peaks
        )
    }

    private static func thumbnails(_ source: TransitionSource) async -> ([CGImage], Double) {
        let count = min(60, max(8, Int(source.duration)))
        let interval = source.duration / Double(count)
        let gen = AVAssetImageGenerator(asset: source.asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 200, height: 200)
        gen.requestedTimeToleranceBefore = TransitionComposer.cm(interval / 2)
        gen.requestedTimeToleranceAfter = TransitionComposer.cm(interval / 2)
        var images: [CGImage] = []
        for i in 0..<count {
            if let (image, _) = try? await gen.image(at: TransitionComposer.cm(interval * (Double(i) + 0.5))) {
                images.append(image)
            } else if let last = images.last {
                images.append(last)
            }
        }
        return (images, interval)
    }

    private static func waveform(_ url: URL) async -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return [] }
        let sampleRate = 8_000
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1
        ])
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }

        let bucket = sampleRate / peaksPerSecond
        var peaks: [Float] = []
        var current: UInt16 = 0
        var n = 0
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            let count = CMBlockBufferGetDataLength(block) / 2
            var samples = [Int16](repeating: 0, count: count)
            samples.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * 2, destination: raw.baseAddress!)
            }
            for s in samples {
                current = max(current, s.magnitude)
                n += 1
                if n == bucket {
                    peaks.append(Float(current) / 32_768)
                    current = 0
                    n = 0
                }
            }
        }
        let top = peaks.max() ?? 0
        return top > 0 ? peaks.map { $0 / top } : peaks
    }
}
