//
//  ImageProcessing.swift
//  GlyphCanvas
//
//  Created by Codex on 4/16/26.
//

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import simd

struct PixelRegion: Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

extension PixelRegion: Equatable {
    nonisolated static func == (lhs: PixelRegion, rhs: PixelRegion) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y && lhs.width == rhs.width && lhs.height == rhs.height
    }
}

extension PixelRegion: Codable {
    private enum CodingKeys: String, CodingKey {
        case x, y, width, height
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decode(Int.self, forKey: .x)
        y = try c.decode(Int.self, forKey: .y)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
    }
}

struct RGBAColor: Sendable {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8

    nonisolated var cgColor: CGColor {
        CGColor(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: CGFloat(a) / 255.0
        )
    }
}

extension RGBAColor: Equatable {
    nonisolated static func == (lhs: RGBAColor, rhs: RGBAColor) -> Bool {
        lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b && lhs.a == rhs.a
    }
}

extension RGBAColor: Codable {
    private enum CodingKeys: String, CodingKey {
        case r, g, b, a
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        r = try c.decode(UInt8.self, forKey: .r)
        g = try c.decode(UInt8.self, forKey: .g)
        b = try c.decode(UInt8.self, forKey: .b)
        a = try c.decode(UInt8.self, forKey: .a)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(r, forKey: .r)
        try c.encode(g, forKey: .g)
        try c.encode(b, forKey: .b)
        try c.encode(a, forKey: .a)
    }
}

final class PixelBuffer: @unchecked Sendable {
    nonisolated let width: Int
    nonisolated let height: Int
    nonisolated let bytesPerRow: Int
    nonisolated let bytesPerPixel: Int = 4
    nonisolated(unsafe) let data: UnsafeMutablePointer<UInt8>

    nonisolated init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.bytesPerRow = width * bytesPerPixel
        self.data = .allocate(capacity: height * bytesPerRow)
        self.data.initialize(repeating: 0, count: height * bytesPerRow)
    }

    deinit {
        data.deallocate()
    }

    /// Copies row-major RGBA bytes into this buffer (dimensions must match).
    func load(from rgbaBytes: [UInt8]) {
        precondition(rgbaBytes.count == width * height * bytesPerPixel)
        rgbaBytes.withUnsafeBytes { src in
            guard let base = src.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            data.update(from: base, count: rgbaBytes.count)
        }
    }

    func copyRegion(_ region: PixelRegion) -> [UInt8] {
        var copy = [UInt8](repeating: 0, count: region.height * region.width * bytesPerPixel)
        for row in 0..<region.height {
            let sourceOffset = (region.y + row) * bytesPerRow + region.x * bytesPerPixel
            let targetOffset = row * region.width * bytesPerPixel
            copy.withUnsafeMutableBytes { target in
                guard let targetBase = target.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                targetBase.advanced(by: targetOffset).update(
                    from: data.advanced(by: sourceOffset),
                    count: region.width * bytesPerPixel
                )
            }
        }
        return copy
    }

    func restoreRegion(_ region: PixelRegion, from snapshot: [UInt8]) {
        for row in 0..<region.height {
            let destinationOffset = (region.y + row) * bytesPerRow + region.x * bytesPerPixel
            let sourceOffset = row * region.width * bytesPerPixel
            snapshot.withUnsafeBytes { source in
                guard let sourceBase = source.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                data.advanced(by: destinationOffset).update(
                    from: sourceBase.advanced(by: sourceOffset),
                    count: region.width * bytesPerPixel
                )
            }
        }
    }
}

enum ImageProcessingError: Error {
    case decodeFailure
    case contextFailure
}

// MARK: - Luminance / perceptual scoring

/// Rec. 709 luminance weights for linear RGB; used consistently for target and candidate.
/// Per-region scoring: luminance (Rec. 709 weights on 8-bit RGB) plus chroma residuals `B−Y` and `R−Y`.
/// Documented weights match the luminance line used for coverage-aware character picking.
enum PerceptualScoring {
    static let redWeight: Double = 0.2126
    static let greenWeight: Double = 0.7152
    static let blueWeight: Double = 0.0722

    /// `score = 0.7 * luminanceMSE + 0.3 * chromaMSE` (lower is better).
    static let luminanceTermWeight: Double = 0.7
    static let chromaTermWeight: Double = 0.3
}

/// Tunable weights for edge-guided encoding loss (mean terms in 0…1 space).
enum EdgeGuidedScoring {
    static let lambdaOffEdge: Double = 1.0
    static let lambdaMissedEdge: Double = 0.85
    /// Minimum edge strength so flat regions still penalize stray ink in `(1 - e)`.
    static let edgeStrengthFloor: Double = 0.04
}

enum ImageProcessing {
    /// Legacy full set (reference / tests).
    static let candidateCharacters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,:;!?@#$%&*+-=/\\|()[]{}")

    /// Rough ink density for a stamp (word, emoji cluster, or single character). Unknown scalars default to mid.
    static func nominalInkDensity(for stamp: String) -> Double {
        guard !stamp.isEmpty else { return 0.5 }
        var sum = 0.0
        var n = 0
        for ch in stamp {
            sum += nominalInkDensity(for: ch)
            n += 1
        }
        let avg = sum / Double(max(1, n))
        let lengthBias = 0.012 * Double(min(stamp.count, 32))
        return min(1.0, avg + lengthBias)
    }

    /// Rough ink density for coverage-aware bucketing (0 = light, 1 = heavy). Unknown characters default to mid.
    private static func nominalInkDensity(for character: Character) -> Double {
        let table: [Character: Double] = [
            "@": 1.0, "#": 1.0, "%": 0.95, "&": 0.9, "W": 0.95, "w": 0.9, "M": 0.95, "m": 0.85,
            "Q": 0.85,
            "A": 0.75, "B": 0.72, "D": 0.72, "G": 0.72, "H": 0.7, "K": 0.72, "N": 0.72, "R": 0.72, "U": 0.72,
            "a": 0.55, "b": 0.58, "d": 0.58, "g": 0.58, "h": 0.52, "k": 0.58, "n": 0.52, "u": 0.52,
            "C": 0.68, "O": 0.78, "S": 0.65, "c": 0.5, "o": 0.62, "s": 0.52,
            "I": 0.35, "i": 0.32, "l": 0.3, "L": 0.38, "J": 0.4, "j": 0.38, "T": 0.4, "t": 0.35, "f": 0.35, "F": 0.42,
            "E": 0.62, "e": 0.48, "P": 0.68, "p": 0.55, "V": 0.65, "v": 0.48, "X": 0.68, "x": 0.52, "Y": 0.65, "y": 0.55,
            "Z": 0.62, "z": 0.5, "q": 0.62,
            ".": 0.08, ",": 0.06, ":": 0.12, ";": 0.12, "'": 0.06, "`": 0.06, "\"": 0.1,
            "!": 0.15, "?": 0.45, "(": 0.35, ")": 0.35, "[": 0.35, "]": 0.35, "{": 0.35, "}": 0.35,
            "-": 0.12, "_": 0.15, "+": 0.35, "=": 0.25, "*": 0.55, "/": 0.35, "\\": 0.35, "|": 0.15,
            "0": 0.72, "8": 0.78, "6": 0.68, "9": 0.72, "4": 0.65, "3": 0.68, "2": 0.55, "5": 0.62, "7": 0.55, "1": 0.25,
            " ": 0.05
        ]
        return table[character] ?? 0.5
    }

    /// Splits the user pool into three non-empty density tiers (high → low ink) for luminance-biased sampling.
    private static func densityTiers(from pool: [String]) -> (dense: [String], medium: [String], light: [String]) {
        let sortedPairs = pool.map { ($0, nominalInkDensity(for: $0)) }.sorted { $0.1 > $1.1 }
        let chars = sortedPairs.map(\.0)
        let n = chars.count
        if n == 0 { return (["?"], ["?"], ["?"]) }
        if n == 1 {
            let c = chars[0]
            return ([c], [c], [c])
        }
        if n == 2 {
            return ([chars[0]], [chars[1]], [chars[1]])
        }
        let d = n / 3
        let m = n / 3
        let dense = Array(chars[0..<d])
        let medium = Array(chars[d..<(d + m)])
        let light = Array(chars[(d + m)..<n])
        return (dense, medium, light)
    }

    /// Quantized font size steps for cache keys (0.25 pt).
    static func quantizedFontSize(_ size: CGFloat) -> CGFloat {
        (size * 4).rounded() / 4
    }

    /// Nearest 5° for cache keys and temporal smoothing.
    static func quantizedRotationDegrees(_ radians: CGFloat) -> Int {
        let deg = radians * 180 / .pi
        return Int((deg / 5.0).rounded()) * 5
    }

    static func radians(fromQuantizedDegrees q: Int) -> CGFloat {
        CGFloat(q) * .pi / 180
    }

    // MARK: Representative color

    /// Returns RGB in **0…255** float space (documented contract for `representativeColor`).
    static func representativeColor(for region: CGRect, in image: CGImage) -> SIMD3<Float> {
        let w = image.width
        let h = image.height
        let x0 = max(0, min(w - 1, Int(region.origin.x.rounded(.down))))
        let y0 = max(0, min(h - 1, Int(region.origin.y.rounded(.down))))
        let x1 = max(x0, min(w, Int(region.maxX.rounded(.up))))
        let y1 = max(y0, min(h, Int(region.maxY.rounded(.up))))
        let pr = PixelRegion(x: x0, y: y0, width: max(1, x1 - x0), height: max(1, y1 - y0))
        guard let buf = try? makePixelBuffer(from: image) else {
            return SIMD3<Float>(128, 128, 128)
        }
        return representativeColor(in: pr, from: buf)
    }

    /// Fast path when `PixelBuffer` is already available (e.g. target image).
    static func representativeColor(in region: PixelRegion, from buffer: PixelBuffer) -> SIMD3<Float> {
        let count = max(1, region.width * region.height)
        var sumR: Double = 0
        var sumG: Double = 0
        var sumB: Double = 0
        var sumR2: Double = 0
        var sumG2: Double = 0
        var sumB2: Double = 0

        var hist = [Int](repeating: 0, count: 64)
        for row in 0..<region.height {
            for col in 0..<region.width {
                let o = (region.y + row) * buffer.bytesPerRow + (region.x + col) * buffer.bytesPerPixel
                let r = Int(buffer.data[o])
                let g = Int(buffer.data[o + 1])
                let b = Int(buffer.data[o + 2])
                sumR += Double(r)
                sumG += Double(g)
                sumB += Double(b)
                sumR2 += Double(r * r)
                sumG2 += Double(g * g)
                sumB2 += Double(b * b)

                let br = min(3, r / 64)
                let bg = min(3, g / 64)
                let bb = min(3, b / 64)
                let bin = br + bg * 4 + bb * 16
                hist[bin] += 1
            }
        }

        let n = Double(count)
        let meanR = sumR / n
        let meanG = sumG / n
        let meanB = sumB / n
        let varR = max(0, sumR2 / n - meanR * meanR)
        let varG = max(0, sumG2 / n - meanG * meanG)
        let varB = max(0, sumB2 / n - meanB * meanB)
        let maxVar = max(varR, varG, varB)

        // Low variance → mean; high variance → dominant 4×4×4 bin center.
        let varianceThreshold = 400.0
        if maxVar < varianceThreshold {
            return SIMD3<Float>(Float(meanR), Float(meanG), Float(meanB))
        }

        var bestBin = 0
        var bestCount = 0
        for i in 0..<64 where hist[i] > bestCount {
            bestCount = hist[i]
            bestBin = i
        }
        let br = bestBin % 4
        let bg = (bestBin / 4) % 4
        let bb = bestBin / 16
        let centerR = Float(br * 64 + 32)
        let centerG = Float(bg * 64 + 32)
        let centerB = Float(bb * 64 + 32)
        return SIMD3<Float>(centerR, centerG, centerB)
    }

    static func rgbaColor(from rgb: SIMD3<Float>, alpha: Float = 255) -> RGBAColor {
        RGBAColor(
            r: UInt8(max(0, min(255, rgb.x)).rounded()),
            g: UInt8(max(0, min(255, rgb.y)).rounded()),
            b: UInt8(max(0, min(255, rgb.z)).rounded()),
            a: UInt8(max(0, min(255, alpha)).rounded())
        )
    }

    /// Maps UI fidelity in `1...8` to RGB quantization step size.
    /// `8 -> 1` (no quantization), `1 -> 128` (very coarse).
    static func colorQuantizationStep(forFidelity fidelity: Double) -> Int {
        let clamped = max(1, min(8, Int(fidelity.rounded())))
        return 1 << (8 - clamped)
    }

    static func quantizeChannel(_ value: UInt8, step: Int) -> UInt8 {
        let s = max(1, step)
        if s == 1 { return value }
        let bucket = Int(value) / s
        let center = bucket * s + s / 2
        return UInt8(min(255, max(0, center)))
    }

    static func quantizeRGB(_ color: RGBAColor, step: Int) -> RGBAColor {
        RGBAColor(
            r: quantizeChannel(color.r, step: step),
            g: quantizeChannel(color.g, step: step),
            b: quantizeChannel(color.b, step: step),
            a: color.a
        )
    }

    static func quantizeRGB(_ color: RGBAColor, fidelity: Double) -> RGBAColor {
        quantizeRGB(color, step: colorQuantizationStep(forFidelity: fidelity))
    }

    static func quantizeRGB(_ rgb: SIMD3<Float>, step: Int) -> SIMD3<Float> {
        let c = rgbaColor(from: rgb)
        let q = quantizeRGB(c, step: step)
        return SIMD3<Float>(Float(q.r), Float(q.g), Float(q.b))
    }

    /// Mean luminance Y (0…255 scale) over region using target buffer.
    static func meanLuminance(in region: PixelRegion, from buffer: PixelBuffer) -> Double {
        var sumY: Double = 0
        let n = max(1, region.width * region.height)
        for row in 0..<region.height {
            for col in 0..<region.width {
                let o = (region.y + row) * buffer.bytesPerRow + (region.x + col) * buffer.bytesPerPixel
                let r = Double(buffer.data[o])
                let g = Double(buffer.data[o + 1])
                let b = Double(buffer.data[o + 2])
                sumY += PerceptualScoring.redWeight * r + PerceptualScoring.greenWeight * g + PerceptualScoring.blueWeight * b
            }
        }
        return sumY / Double(n)
    }

    /// Picks a stamp biased by mean luminance of the **target** region: dark → denser glyphs, light → lighter glyphs.
    /// Density tiers are recomputed from `stampPool` (tertiles by nominal ink score) so the user’s set drives coverage behavior.
    static func randomCoverageAwareStamp(meanLuminanceY: Double, stampPool: [String]) -> String {
        let pool = stampPool.isEmpty ? ["?"] : stampPool
        let tiers = densityTiers(from: pool)
        let y = meanLuminanceY / 255.0
        let wDense = max(0.05, 1.0 - y)
        let wLight = max(0.05, y)
        let wMed = 0.35
        let sum = wDense + wMed + wLight
        let r = Double.random(in: 0..<sum)
        if r < wDense {
            return tiers.dense.randomElement() ?? pool.randomElement() ?? "?"
        }
        if r < wDense + wMed {
            return tiers.medium.randomElement() ?? pool.randomElement() ?? "?"
        }
        return tiers.light.randomElement() ?? pool.randomElement() ?? "?"
    }

    // MARK: Perceptual error (region-local)

    /// Region-local perceptual difference: luminance MSE + chroma (Cb/Cr vs Y) MSE, combined 0.7/0.3.
    /// `candidate` may be a crop buffer with origin (0,0) matching `region` dimensions; `target` uses full-image coordinates in `region`.
    static func perceptualError(
        candidate: PixelBuffer,
        target: PixelBuffer,
        region: PixelRegion
    ) -> Double {
        precondition(candidate.width == region.width && candidate.height == region.height)

        let w = PerceptualScoring.redWeight
        let wg = PerceptualScoring.greenWeight
        let wb = PerceptualScoring.blueWeight
        var lumAcc: Double = 0
        var chromaAcc: Double = 0
        let pixels = Double(max(1, region.width * region.height))

        for row in 0..<region.height {
            for col in 0..<region.width {
                let co = row * candidate.bytesPerRow + col * candidate.bytesPerPixel
                let to = (region.y + row) * target.bytesPerRow + (region.x + col) * target.bytesPerPixel

                let rc = Double(candidate.data[co])
                let gc = Double(candidate.data[co + 1])
                let bc = Double(candidate.data[co + 2])

                let rt = Double(target.data[to])
                let gt = Double(target.data[to + 1])
                let bt = Double(target.data[to + 2])

                let yc = w * rc + wg * gc + wb * bc
                let yt = w * rt + wg * gt + wb * bt
                let dY = yc - yt
                lumAcc += dY * dY

                let cbc = bc - yc
                let cgc = rc - yc
                let cbt = bt - yt
                let cgt = rt - yt
                let dCb = cbc - cbt
                let dCr = cgc - cgt
                chromaAcc += dCb * dCb + dCr * dCr
            }
        }

        let luminanceMSE = lumAcc / pixels
        let chromaMSE = chromaAcc / (pixels * 2.0)
        return PerceptualScoring.luminanceTermWeight * luminanceMSE
            + PerceptualScoring.chromaTermWeight * chromaMSE
    }

    /// Mean perceptual error for a subregion of two full same-size buffers (e.g. canvas vs target).
    static func perceptualErrorAligned(
        candidate: PixelBuffer,
        target: PixelBuffer,
        region: PixelRegion
    ) -> Double {
        var lumAcc: Double = 0
        var chromaAcc: Double = 0
        let w = PerceptualScoring.redWeight
        let wg = PerceptualScoring.greenWeight
        let wb = PerceptualScoring.blueWeight
        let pixels = Double(max(1, region.width * region.height))

        for row in 0..<region.height {
            for col in 0..<region.width {
                let o = (region.y + row) * candidate.bytesPerRow + (region.x + col) * candidate.bytesPerPixel
                let rc = Double(candidate.data[o])
                let gc = Double(candidate.data[o + 1])
                let bc = Double(candidate.data[o + 2])
                let rt = Double(target.data[o])
                let gt = Double(target.data[o + 1])
                let bt = Double(target.data[o + 2])

                let yc = w * rc + wg * gc + wb * bc
                let yt = w * rt + wg * gt + wb * bt
                lumAcc += (yc - yt) * (yc - yt)

                let dCb = (bc - yc) - (bt - yt)
                let dCr = (rc - yc) - (rt - yt)
                chromaAcc += dCb * dCb + dCr * dCr
            }
        }

        let luminanceMSE = lumAcc / pixels
        let chromaMSE = chromaAcc / (pixels * 2.0)
        return PerceptualScoring.luminanceTermWeight * luminanceMSE
            + PerceptualScoring.chromaTermWeight * chromaMSE
    }

    // MARK: Edge strength map (precomputed once per target)

    /// Rec. 709 luminance at a pixel; `x`/`y` clamped to the buffer.
    private static func luminancePixel(buffer: PixelBuffer, x: Int, y: Int) -> Double {
        let xc = min(buffer.width - 1, max(0, x))
        let yc = min(buffer.height - 1, max(0, y))
        let o = yc * buffer.bytesPerRow + xc * buffer.bytesPerPixel
        let r = Double(buffer.data[o])
        let g = Double(buffer.data[o + 1])
        let b = Double(buffer.data[o + 2])
        return PerceptualScoring.redWeight * r + PerceptualScoring.greenWeight * g + PerceptualScoring.blueWeight * b
    }

    /// Sobel magnitude on luminance, normalized to 0…1, mild 3×3 box blur, stored in the **red** channel (G/B = 0, A = 255).
    static func makeEdgeStrengthBuffer(from target: PixelBuffer) -> PixelBuffer {
        let w = target.width
        let h = target.height
        var lum = [Double](repeating: 0, count: w * h)
        var mag = [Double](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                lum[y * w + x] = luminancePixel(buffer: target, x: x, y: y)
            }
        }
        func L(_ x: Int, _ y: Int) -> Double {
            lum[min(h - 1, max(0, y)) * w + min(w - 1, max(0, x))]
        }
        for y in 0..<h {
            for x in 0..<w {
                let gx =
                    -L(x - 1, y - 1) + L(x + 1, y - 1)
                    + -2 * L(x - 1, y) + 2 * L(x + 1, y)
                    + -L(x - 1, y + 1) + L(x + 1, y + 1)
                let gy =
                    -L(x - 1, y - 1) - 2 * L(x, y - 1) - L(x + 1, y - 1)
                    + L(x - 1, y + 1) + 2 * L(x, y + 1) + L(x + 1, y + 1)
                mag[y * w + x] = sqrt(gx * gx + gy * gy)
            }
        }
        var maxM = 1e-9
        for v in mag { if v > maxM { maxM = v } }
        var norm = [Double](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            norm[i] = mag[i] / maxM
        }
        // Light box blur on normalized magnitudes.
        var blurred = [Double](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var s = 0.0
                var c = 0.0
                for dy in -1...1 {
                    for dx in -1...1 {
                        let xx = min(w - 1, max(0, x + dx))
                        let yy = min(h - 1, max(0, y + dy))
                        s += norm[yy * w + xx]
                        c += 1
                    }
                }
                blurred[y * w + x] = s / c
            }
        }
        let out = PixelBuffer(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w {
                let e = blurred[y * w + x]
                let er = UInt8(min(255, max(0, (e * 255.0).rounded())))
                let o = y * out.bytesPerRow + x * out.bytesPerPixel
                out.data[o] = er
                out.data[o + 1] = 0
                out.data[o + 2] = 0
                out.data[o + 3] = 255
            }
        }
        return out
    }

    // MARK: Edge-guided loss (encoding mode `.edges`)

    /// Encourages stamp ink on strong target edges and coverage where edges are strong; primary signal is ink deviation from the canvas background.
    private static func ink01(r: Double, g: Double, b: Double, background: RGBAColor) -> Double {
        let br = Double(background.r)
        let bg = Double(background.g)
        let bb = Double(background.b)
        let d = max(abs(r - br), abs(g - bg), abs(b - bb))
        return min(1, d / 255.0)
    }

    /// Region-local edge loss for a crop buffer aligned to `region` (same layout as `perceptualError`).
    static func edgeGuidedLoss(
        candidate: PixelBuffer,
        edgeStrength: PixelBuffer,
        region: PixelRegion,
        canvasBackground: RGBAColor
    ) -> Double {
        precondition(candidate.width == region.width && candidate.height == region.height)
        precondition(region.x >= 0 && region.y >= 0 && region.x + region.width <= edgeStrength.width && region.y + region.height <= edgeStrength.height)

        var offAcc: Double = 0
        var missAcc: Double = 0
        let floorE = EdgeGuidedScoring.edgeStrengthFloor
        let pixels = Double(max(1, region.width * region.height))

        for row in 0..<region.height {
            for col in 0..<region.width {
                let co = row * candidate.bytesPerRow + col * candidate.bytesPerPixel
                let rc = Double(candidate.data[co])
                let gc = Double(candidate.data[co + 1])
                let bc = Double(candidate.data[co + 2])
                let ink = ink01(r: rc, g: gc, b: bc, background: canvasBackground)

                let to = (region.y + row) * edgeStrength.bytesPerRow + (region.x + col) * edgeStrength.bytesPerPixel
                let eRaw = Double(edgeStrength.data[to]) / 255.0
                let e = max(eRaw, floorE)

                offAcc += ink * (1.0 - e)
                missAcc += e * (1.0 - ink)
            }
        }

        let offMean = offAcc / pixels
        let missMean = missAcc / pixels
        return EdgeGuidedScoring.lambdaOffEdge * offMean + EdgeGuidedScoring.lambdaMissedEdge * missMean
    }

    /// Mean edge-guided loss for a subregion of two full same-size buffers (e.g. canvas vs edge map).
    static func edgeGuidedLossAligned(
        candidate: PixelBuffer,
        edgeStrength: PixelBuffer,
        region: PixelRegion,
        canvasBackground: RGBAColor
    ) -> Double {
        precondition(candidate.width == edgeStrength.width && candidate.height == edgeStrength.height)

        var offAcc: Double = 0
        var missAcc: Double = 0
        let floorE = EdgeGuidedScoring.edgeStrengthFloor
        let pixels = Double(max(1, region.width * region.height))

        for row in 0..<region.height {
            for col in 0..<region.width {
                let o = (region.y + row) * candidate.bytesPerRow + (region.x + col) * candidate.bytesPerPixel
                let rc = Double(candidate.data[o])
                let gc = Double(candidate.data[o + 1])
                let bc = Double(candidate.data[o + 2])
                let ink = ink01(r: rc, g: gc, b: bc, background: canvasBackground)

                let eRaw = Double(edgeStrength.data[o]) / 255.0
                let e = max(eRaw, floorE)

                offAcc += ink * (1.0 - e)
                missAcc += e * (1.0 - ink)
            }
        }

        let offMean = offAcc / pixels
        let missMean = missAcc / pixels
        return EdgeGuidedScoring.lambdaOffEdge * offMean + EdgeGuidedScoring.lambdaMissedEdge * missMean
    }

    /// Dispatches region loss for candidate scratch vs target (perceptual or edge-guided).
    static func regionEncodingLoss(
        mode: EncodingComparisonMode,
        candidate: PixelBuffer,
        target: PixelBuffer,
        edgeStrength: PixelBuffer,
        region: PixelRegion,
        canvasBackground: RGBAColor
    ) -> Double {
        switch mode {
        case .perceptual:
            return perceptualError(candidate: candidate, target: target, region: region)
        case .edges:
            return edgeGuidedLoss(
                candidate: candidate,
                edgeStrength: edgeStrength,
                region: region,
                canvasBackground: canvasBackground
            )
        }
    }

    /// Dispatches aligned region loss for full canvas vs target (perceptual or edge-guided).
    static func regionEncodingLossAligned(
        mode: EncodingComparisonMode,
        candidate: PixelBuffer,
        target: PixelBuffer,
        edgeStrength: PixelBuffer,
        region: PixelRegion,
        canvasBackground: RGBAColor
    ) -> Double {
        switch mode {
        case .perceptual:
            return perceptualErrorAligned(candidate: candidate, target: target, region: region)
        case .edges:
            return edgeGuidedLossAligned(
                candidate: candidate,
                edgeStrength: edgeStrength,
                region: region,
                canvasBackground: canvasBackground
            )
        }
    }

    /// Decodes image data to a `CGImage` with EXIF orientation applied to pixel data (upright bitmap).
    /// Uses `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailWithTransform` so
    /// library/file/URL imports match Photos; falls back to raw decode if thumbnail creation fails.
    static func decodeCGImage(data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        func intDimension(_ key: CFString) -> Int {
            if let v = properties[key] as? Int { return v }
            if let v = properties[key] as? CGFloat { return Int(v.rounded()) }
            if let v = properties[key] as? Double { return Int(v.rounded()) }
            if let n = properties[key] as? NSNumber { return n.intValue }
            return 0
        }
        let width = intDimension(kCGImagePropertyPixelWidth)
        let height = intDimension(kCGImagePropertyPixelHeight)
        guard width > 0, height > 0 else {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        let maxSide = max(width, height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        if let oriented = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return oriented
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - Import adjust (rotate / crop)

    /// Bitmap context with Core Graphics default coordinate system (origin bottom-left, +y up). Used for lossless quarter-turn rotation.
    nonisolated private static func makeBitmapContextUnflipped(width: Int, height: Int) -> CGContext? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )
    }

    /// Rotates the image in 90° steps. Positive `quarterTurns` = counterclockwise (same sense as `rotate.left` in Photos).
    /// Returns `nil` if a new bitmap cannot be allocated.
    nonisolated static func cgImageRotatedQuarterTurns(_ image: CGImage, quarterTurns: Int) -> CGImage? {
        let q = ((quarterTurns % 4) + 4) % 4
        guard q != 0 else { return image }
        let w = image.width
        let h = image.height
        let outW: Int
        let outH: Int
        if q == 2 {
            outW = w
            outH = h
        } else {
            outW = h
            outH = w
        }
        guard let ctx = makeBitmapContextUnflipped(width: outW, height: outH) else { return nil }
        ctx.interpolationQuality = .high
        let wf = CGFloat(w)
        let hf = CGFloat(h)
        switch q {
        case 1:
            // 90° CCW
            ctx.translateBy(x: 0, y: wf)
            ctx.rotate(by: -.pi / 2)
        case 2:
            ctx.translateBy(x: wf, y: hf)
            ctx.rotate(by: .pi)
        case 3:
            // 90° CW
            ctx.translateBy(x: hf, y: 0)
            ctx.rotate(by: .pi / 2)
        default:
            break
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: wf, height: hf))
        return ctx.makeImage()
    }

    /// Crops using a normalized rectangle in **top-left** image coordinates (matches SwiftUI layout): origin (0,0) is the top-left of the image, y increases downward.
    nonisolated static func cgImageCroppingNormalizedTopLeft(_ image: CGImage, normalizedRect: CGRect) -> CGImage? {
        let iw = CGFloat(image.width)
        let ih = CGFloat(image.height)
        guard iw >= 1, ih >= 1 else { return nil }

        var nx = max(0, min(1, normalizedRect.origin.x))
        var ny = max(0, min(1, normalizedRect.origin.y))
        var nw = max(0, min(1 - nx, normalizedRect.size.width))
        var nh = max(0, min(1 - ny, normalizedRect.size.height))
        guard nw > 0, nh > 0 else { return nil }

        // CGImage cropping uses bottom-left origin.
        var crop = CGRect(
            x: nx * iw,
            y: (1.0 - ny - nh) * ih,
            width: nw * iw,
            height: nh * ih
        )
        crop = crop.integral
        crop.origin.x = floor(crop.origin.x)
        crop.origin.y = floor(crop.origin.y)
        crop.size.width = max(1, ceil(crop.size.width))
        crop.size.height = max(1, ceil(crop.size.height))

        let bounds = CGRect(x: 0, y: 0, width: iw, height: ih)
        crop = crop.intersection(bounds)
        guard crop.width >= 1, crop.height >= 1 else { return nil }
        return image.cropping(to: crop)
    }

    static func downscaledImage(_ image: CGImage, maxDimension: Int) throws -> CGImage {
        let sourceWidth = image.width
        let sourceHeight = image.height
        let longest = max(sourceWidth, sourceHeight)
        guard longest > maxDimension else {
            return image
        }

        let scale = CGFloat(maxDimension) / CGFloat(longest)
        let targetWidth = max(Int((CGFloat(sourceWidth) * scale).rounded()), 1)
        let targetHeight = max(Int((CGFloat(sourceHeight) * scale).rounded()), 1)

        guard let context = makeContext(width: targetWidth, height: targetHeight, data: nil) else {
            throw ImageProcessingError.contextFailure
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let downscaled = context.makeImage() else {
            throw ImageProcessingError.contextFailure
        }
        return downscaled
    }

    static func makePixelBuffer(from image: CGImage) throws -> PixelBuffer {
        let buffer = PixelBuffer(width: image.width, height: image.height)
        guard let context = makeContext(width: image.width, height: image.height, data: buffer.data) else {
            throw ImageProcessingError.contextFailure
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }

    /// Samples up to `maxSamples` pixels (spread across the image), buckets RGB into 8³ coarse bins,
    /// takes the five most frequent bins, and returns the **darkest** bin center by Rec. 709 luminance.
    /// Nearly transparent samples are skipped. Falls back to white if nothing usable is sampled.
    nonisolated static func darkestAmongTopFiveCommonColors(from image: CGImage, maxSamples: Int = 500) throws -> RGBAColor {
        let buffer = try makePixelBuffer(from: image)
        let w = buffer.width
        let h = buffer.height
        let n = max(1, w * h)
        let sampleCount = min(max(1, maxSamples), n)
        var counts: [UInt32: Int] = [:]
        for k in 0..<sampleCount {
            let idx = (k * n) / sampleCount
            let y = idx / w
            let x = idx % w
            let o = y * buffer.bytesPerRow + x * buffer.bytesPerPixel
            let a = buffer.data[o + 3]
            if a < 10 { continue }
            let r = buffer.data[o]
            let g = buffer.data[o + 1]
            let b = buffer.data[o + 2]
            let qr = Int(r) >> 5
            let qg = Int(g) >> 5
            let qb = Int(b) >> 5
            let key = UInt32((qr << 6) | (qg << 3) | qb)
            counts[key, default: 0] += 1
        }
        if counts.isEmpty {
            return RGBAColor(r: 255, g: 255, b: 255, a: 255)
        }
        let sorted = counts.sorted { $0.value > $1.value }
        let top = min(5, sorted.count)
        var bestLum = Double.infinity
        var bestColor = RGBAColor(r: 255, g: 255, b: 255, a: 255)
        for i in 0..<top {
            let key = sorted[i].key
            let qb = Int(key & 7)
            let qg = Int((key >> 3) & 7)
            let qr = Int((key >> 6) & 7)
            let rc = UInt8(min(255, qr * 32 + 16))
            let gc = UInt8(min(255, qg * 32 + 16))
            let bc = UInt8(min(255, qb * 32 + 16))
            let rf = Double(rc)
            let gf = Double(gc)
            let bf = Double(bc)
            let lum =
                PerceptualScoring.redWeight * rf
                + PerceptualScoring.greenWeight * gf
                + PerceptualScoring.blueWeight * bf
            if lum < bestLum {
                bestLum = lum
                bestColor = RGBAColor(r: rc, g: gc, b: bc, a: 255)
            }
        }
        return bestColor
    }

    nonisolated static func makeContext(width: Int, height: Int, data: UnsafeMutableRawPointer?) -> CGContext? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        // CoreText uses `textMatrix` with the CTM; default can mirror glyphs in a flipped bitmap context.
        context.textMatrix = .identity
        return context
    }

    static func clampedRegion(
        centerX: Int,
        centerY: Int,
        regionSize: Int,
        width: Int,
        height: Int
    ) -> PixelRegion {
        let half = regionSize / 2
        let x = max(0, min(width - regionSize, centerX - half))
        let y = max(0, min(height - regionSize, centerY - half))
        let w = min(regionSize, width - x)
        let h = min(regionSize, height - y)
        return PixelRegion(x: x, y: y, width: w, height: h)
    }

    static func averageColor(in region: PixelRegion, from buffer: PixelBuffer) -> RGBAColor {
        rgbaColor(from: representativeColor(in: region, from: buffer))
    }

    // MARK: Typewriter font (Courier / Courier New preferred, Menlo fallback)

    nonisolated private static func baseTypewriterFont(size: CGFloat) -> CTFont {
        for name in ["Courier", "Courier New", "Menlo"] {
            let font = CTFontCreateWithName(name as CFString, size, nil)
            let ps = CTFontCopyPostScriptName(font) as String
            if ps.lowercased().contains("courier") || ps.contains("Menlo") {
                return font
            }
        }
        return CTFontCreateWithName("Menlo" as CFString, size, nil)
    }

    nonisolated static func typewriterFont(size: CGFloat, bold: Bool = false) -> CTFont {
        let base = baseTypewriterFont(size: size)
        guard bold else { return base }
        let boldTraits = CTFontSymbolicTraits.traitBold
        if let withTraits = CTFontCreateCopyWithSymbolicTraits(base, size, nil, boldTraits, boldTraits) {
            return withTraits
        }
        return base
    }

    // MARK: Drawing

    nonisolated static func makeAttributedLine(character: String, fontSize: CGFloat, color: RGBAColor, bold: Bool = false) -> CTLine {
        let ctFont = typewriterFont(size: fontSize, bold: bold)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(rawValue: kCTFontAttributeName as String): ctFont,
            NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): color.cgColor
        ]
        let attributed = NSAttributedString(string: character, attributes: attributes)
        return CTLineCreateWithAttributedString(attributed)
    }

    nonisolated static func drawGlyph(
        _ glyph: GlyphCandidate,
        in context: CGContext
    ) {
        let center = CGPoint(
            x: CGFloat(glyph.region.x) + CGFloat(glyph.region.width) / 2.0 + glyph.centerOffsetX,
            y: CGFloat(glyph.region.y) + CGFloat(glyph.region.height) / 2.0 + glyph.centerOffsetY
        )
        let line = makeAttributedLine(character: glyph.character, fontSize: glyph.fontSize, color: glyph.color, bold: glyph.isBold)
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds, .useOpticalBounds])

        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: glyph.rotationRadians)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// Renders a single glyph with rotation into a tight transparent bitmap (for caching).
    static func renderGlyphBitmap(
        character: String,
        fontSize: CGFloat,
        rotationRadians: CGFloat,
        color: RGBAColor,
        isBold: Bool = false
    ) -> CGImage? {
        let line = makeAttributedLine(character: character, fontSize: fontSize, color: color, bold: isBold)
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds, .useOpticalBounds])
        let pad: CGFloat = 4
        let rot = abs(rotationRadians)
        let cosR = abs(cos(rot))
        let sinR = abs(sin(rot))
        let bw = bounds.width * cosR + bounds.height * sinR
        let bh = bounds.width * sinR + bounds.height * cosR
        let rw = max(8, Int(ceil(bw + pad * 2)))
        let rh = max(8, Int(ceil(bh + pad * 2)))

        guard let ctx = makeContext(width: rw, height: rh, data: nil) else { return nil }
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high
        ctx.clear(CGRect(x: 0, y: 0, width: rw, height: rh))

        let cx = CGFloat(rw) / 2
        let cy = CGFloat(rh) / 2
        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: rotationRadians)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()

        return ctx.makeImage()
    }

    /// Composites a cached glyph bitmap onto `scratchContext` centered in the scratch buffer (region-sized).
    static func compositeCachedGlyph(
        _ image: CGImage,
        scratchWidth: Int,
        scratchHeight: Int,
        offsetX: CGFloat = 0,
        offsetY: CGFloat = 0,
        in scratchContext: CGContext
    ) {
        scratchContext.saveGState()
        scratchContext.setBlendMode(.normal)
        let iw = CGFloat(image.width)
        let ih = CGFloat(image.height)
        let cx = CGFloat(scratchWidth) / 2 + offsetX
        let cy = CGFloat(scratchHeight) / 2 + offsetY
        let rect = CGRect(x: cx - iw / 2, y: cy - ih / 2, width: iw, height: ih)
        scratchContext.draw(image, in: rect)
        scratchContext.restoreGState()
    }
}

// MARK: - Glyph render cache

struct GlyphRenderKey: Hashable, Sendable {
    private static let fieldSep = "\u{1E}"
    let stamp: String
    let quantizedFontSize: CGFloat
    let quantizedRotationDegrees: Int
    let quantizedR: UInt8
    let quantizedG: UInt8
    let quantizedB: UInt8
    let isBold: Bool

    var nsCacheKey: NSString {
        "\(stamp)\(Self.fieldSep)\(quantizedFontSize)\(Self.fieldSep)\(quantizedRotationDegrees)\(Self.fieldSep)\(quantizedR)\(Self.fieldSep)\(quantizedG)\(Self.fieldSep)\(quantizedB)\(Self.fieldSep)\(isBold ? 1 : 0)" as NSString
    }

    static func quantizeRGB(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> (UInt8, UInt8, UInt8) {
        (r / 32 * 32, g / 32 * 32, b / 32 * 32)
    }

    init(glyph: GlyphCandidate) {
        stamp = glyph.character.isEmpty ? "?" : glyph.character
        quantizedFontSize = ImageProcessing.quantizedFontSize(glyph.fontSize)
        quantizedRotationDegrees = ImageProcessing.quantizedRotationDegrees(glyph.rotationRadians)
        let q = Self.quantizeRGB(glyph.color.r, glyph.color.g, glyph.color.b)
        quantizedR = q.0
        quantizedG = q.1
        quantizedB = q.2
        isBold = glyph.isBold
    }
}

final class GlyphBitmapCache: @unchecked Sendable {
    private let cache = NSCache<NSString, CGImage>()

    func image(for key: GlyphRenderKey, create: () -> CGImage?) -> CGImage? {
        if let existing = cache.object(forKey: key.nsCacheKey) {
            return existing
        }
        guard let built = create() else { return nil }
        cache.setObject(built, forKey: key.nsCacheKey)
        return built
    }
}

// MARK: - PNG export

enum PNGExport {
    nonisolated static func data(from cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

/// Perceptual similarity for two full images over a CGRect (uses one shared perceptual metric).
func similarityScore(candidate: CGImage, target: CGImage, region: CGRect) -> Double {
    guard
        let candidateBuffer = try? ImageProcessing.makePixelBuffer(from: candidate),
        let targetBuffer = try? ImageProcessing.makePixelBuffer(from: target)
    else {
        return .infinity
    }

    let pixelRegion = PixelRegion(
        x: max(0, Int(region.origin.x)),
        y: max(0, Int(region.origin.y)),
        width: max(1, min(candidateBuffer.width - max(0, Int(region.origin.x)), Int(region.width))),
        height: max(1, min(candidateBuffer.height - max(0, Int(region.origin.y)), Int(region.height)))
    )

    return ImageProcessing.perceptualErrorAligned(
        candidate: candidateBuffer,
        target: targetBuffer,
        region: pixelRegion
    )
}
