//
//  CaptionOverlay.swift
//  GlyphCanvas
//
//  Glyph captions: transcribe a video's speech into caption lines, then paint each frame with the
//  words of the line being spoken. Words fill the bottom 10% solid and thin out (randomly) to nothing
//  at half height. Output is burned in, so no caption track is needed.
//

import AVFoundation
import CoreImage
import CoreText
import Speech

nonisolated struct CaptionLine: Identifiable, Equatable, Sendable {
    var id = UUID()
    var start: Double
    var end: Double
    var text: String
}

nonisolated struct CaptionWord: Equatable, Sendable {
    var text: String
    var start: Double
    var end: Double
}

// MARK: - Transcription

nonisolated enum CaptionTranscriber {
    /// Joins words into caption lines, breaking on pauses and length.
    static func lines(from words: [CaptionWord], maxChars: Int = 32, maxGap: Double = 0.7) -> [CaptionLine] {
        var lines: [CaptionLine] = []
        for word in words {
            if var last = lines.last,
               word.start - last.end <= maxGap,
               last.text.count + 1 + word.text.count <= maxChars {
                last.text += " " + word.text
                last.end = word.end
                lines[lines.count - 1] = last
            } else {
                lines.append(CaptionLine(start: word.start, end: word.end, text: word.text))
            }
        }
        return lines
    }

    static func transcribe(_ source: TransitionSource, progress: @escaping @Sendable (Double) -> Void) async throws -> [CaptionLine] {
        guard let audio = source.audio else {
            throw error("That video has no audio to caption.")
        }
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else {
            throw error("Allow speech recognition in Settings to make captions.")
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw error("Speech recognition isn't available for your language right now.")
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        // On-device has no length limit and keeps audio private.
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let reader = try AVAssetReader(asset: source.asset)
        let output = AVAssetReaderTrackOutput(track: audio, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1
        ])
        guard reader.canAdd(output) else { throw error("Couldn't read that video's audio.") }
        reader.add(output)

        let state = TranscriptState()
        let words: [CaptionWord] = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                state.continuation = cont
                state.task = recognizer.recognitionTask(with: request) { result, err in
                    if let result { state.merge(result) }
                    if result?.isFinal == true {
                        state.finish(nil)
                    } else if let err {
                        state.finish(err)
                    }
                }
                guard reader.startReading() else {
                    state.finish(Self.error("Couldn't read that video's audio."))
                    return
                }
                Task.detached {
                    while state.isRunning, let buffer = output.copyNextSampleBuffer() {
                        request.appendAudioSampleBuffer(buffer)
                        progress(min(1, CMSampleBufferGetPresentationTimeStamp(buffer).seconds / max(0.1, source.duration)))
                    }
                    request.endAudio()
                }
            }
        } onCancel: {
            state.task?.cancel()
        }
        return lines(from: words)
    }

    static func error(_ message: String) -> NSError {
        NSError(domain: "GlyphCaptions", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// Collects recognized words across results; the recognizer may restart its transcript after long pauses.
private nonisolated final class TranscriptState: @unchecked Sendable {
    private let lock = NSLock()
    private var words: [CaptionWord] = []
    private var done = false
    var continuation: CheckedContinuation<[CaptionWord], Error>?
    var task: SFSpeechRecognitionTask?

    var isRunning: Bool { lock.withLock { !done } }

    func merge(_ result: SFSpeechRecognitionResult) {
        let fresh = result.bestTranscription.segments.map {
            CaptionWord(text: $0.substring, start: $0.timestamp, end: $0.timestamp + $0.duration)
        }
        guard let first = fresh.first else { return }
        lock.withLock {
            // Same transcript growing → replace the overlap; restarted transcript → append.
            words.removeAll { $0.start >= first.start - 0.01 }
            words += fresh
        }
    }

    func finish(_ error: Error?) {
        let (cont, words): (CheckedContinuation<[CaptionWord], Error>?, [CaptionWord]) = lock.withLock {
            guard !done else { return (nil, []) }
            done = true
            defer { continuation = nil }
            return (continuation, self.words)
        }
        guard let cont else { return }
        // "No speech detected" (1110) and errors after some words still give usable captions.
        if let error, words.isEmpty, (error as NSError).code != 1110 {
            cont.resume(throwing: error)
        } else {
            cont.resume(returning: words)
        }
    }
}

// MARK: - Layout

nonisolated struct CaptionPlacement: Equatable, Sendable {
    var text: String
    /// Bottom-left origin (Core Image / unflipped Core Graphics).
    var center: CGPoint
    var rotation: CGFloat
    var fontSize: CGFloat
}

nonisolated enum CaptionLayout {
    /// Bottom fraction of the frame that is solid text.
    static let solidBand = 0.10
    /// Height fraction where text runs out.
    static let fadeTop = 0.5
    static let ink = RGBAColor(r: 255, g: 255, b: 255, a: 255)

    /// Chance a word survives at this height (0 = bottom, 1 = top).
    static func density(atHeightFraction f: Double) -> Double {
        if f <= solidBand { return 1 }
        if f >= fadeTop { return 0 }
        let p = (fadeTop - f) / (fadeTop - solidBand)
        return p * p
    }

    static func baseFontSize(for size: CGSize) -> CGFloat {
        max(10, min(size.width, size.height) * 0.05)
    }

    /// Rows of the line's words, tiled left to right from the bottom up, randomly dropped by `density`.
    static func placements(text: String, size: CGSize, seed: UInt64) -> [CaptionPlacement] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty, size.width > 0, size.height > 0 else { return [] }
        let base = baseFontSize(for: size)
        var rng = SplitMix(seed: seed)
        var out: [CaptionPlacement] = []
        var next = 0
        var y = base * 0.45
        while Double(y / size.height) < fadeTop {
            let f = Double(y / size.height)
            let solid = f <= solidBand
            var x = -base * (rng.unit() + 1)
            while x < size.width {
                let word = words[next % words.count]
                next += 1
                let fontSize = solid ? base : base * (1 + 0.2 * rng.unit())
                let width = CTLineGetTypographicBounds(
                    ImageProcessing.makeAttributedLine(character: word, fontSize: fontSize, color: ink, bold: true), nil, nil, nil
                )
                let roll = Double(rng.unit() + 1) / 2
                // Sum of three uniforms ≈ normal: mostly upright, occasionally tilted, never flipped.
                let tilt = (rng.unit() + rng.unit() + rng.unit()) / 3
                let jitter = rng.unit()
                if roll < density(atHeightFraction: f) {
                    let spread: CGFloat = solid ? 0.06 : 0.12 + 0.5 * CGFloat(f / fadeTop)
                    out.append(CaptionPlacement(
                        text: word,
                        center: CGPoint(x: x + width / 2, y: y + (solid ? 0 : jitter * base * 0.3)),
                        rotation: min(0.6, max(-0.6, tilt * spread)),
                        fontSize: fontSize
                    ))
                }
                x += width + fontSize * 0.35
            }
            y += base * 0.95
        }
        return out
    }

    static func render(_ placements: [CaptionPlacement], size: CGSize) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setShadow(offset: .zero, blur: baseFontSize(for: size) * 0.25, color: CGColor(gray: 0, alpha: 0.9))
        for p in placements {
            let line = ImageProcessing.makeAttributedLine(character: p.text, fontSize: p.fontSize, color: ink, bold: true)
            let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
            ctx.saveGState()
            ctx.translateBy(x: p.center.x, y: p.center.y)
            ctx.rotate(by: p.rotation)
            ctx.textMatrix = .identity
            ctx.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    static let hold = 0.6
    static let fade = 0.12

    /// Caption shown at `t`. Lines linger briefly so short pauses don't blink.
    static func activeIndex(in lines: [CaptionLine], at t: Double) -> Int? {
        guard let i = lines.lastIndex(where: { $0.start <= t }), t < lines[i].end + hold else { return nil }
        return i
    }

    /// 0...1 fade in at the line's start and out at the end of its hold.
    static func opacity(of line: CaptionLine, at t: Double) -> Double {
        max(0, min(1, (t - line.start) / fade, (line.end + hold - t) / fade))
    }
}

// MARK: - Per-frame compositing

/// Caches one overlay image per caption line; called from AVFoundation's render threads.
nonisolated final class CaptionRenderer: @unchecked Sendable {
    let lines: [CaptionLine]
    /// Fill words with the (boosted) video underneath instead of white.
    let videoInk: Bool
    private let lock = NSLock()
    private var cache: [Int: CIImage] = [:]
    private var cacheSize: CGSize = .zero

    init(lines: [CaptionLine], videoInk: Bool = false) {
        self.lines = lines.sorted { $0.start < $1.start }
        self.videoInk = videoInk
    }

    func overlay(at t: Double, size: CGSize) -> CIImage? {
        guard let i = CaptionLayout.activeIndex(in: lines, at: t) else { return nil }
        let image: CIImage? = lock.withLock {
            if cacheSize != size {
                cache = [:]
                cacheSize = size
            }
            if let hit = cache[i] { return hit }
            let placements = CaptionLayout.placements(text: lines[i].text, size: size, seed: UInt64(i))
            let image = CaptionLayout.render(placements, size: size).map { CIImage(cgImage: $0) }
            cache[i] = image
            return image
        }
        let alpha = CaptionLayout.opacity(of: lines[i], at: t)
        guard let image, alpha < 1 else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
    }

    func composite(_ overlay: CIImage, over source: CIImage) -> CIImage {
        guard videoInk else { return overlay.composited(over: source) }
        // White glyphs × boosted frame = frame-coloured glyphs; the black shadow stays dark.
        let boosted = source.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.8, kCIInputBrightnessKey: 0.15])
        let tinted = overlay.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: boosted])
        return tinted.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: source, kCIInputMaskImageKey: overlay])
    }

    func videoComposition(for asset: AVAsset) async throws -> AVVideoComposition {
        try await AVMutableVideoComposition.videoComposition(with: asset) { [self] request in
            let source = request.sourceImage
            let e = source.extent
            guard let overlay = overlay(at: request.compositionTime.seconds, size: e.size) else {
                request.finish(with: source, context: nil)
                return
            }
            let placed = overlay.transformed(by: CGAffineTransform(translationX: e.minX, y: e.minY))
            request.finish(with: composite(placed, over: source).cropped(to: e), context: nil)
        }
    }
}
