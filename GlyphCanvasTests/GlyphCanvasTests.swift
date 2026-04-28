//
//  GlyphCanvasTests.swift
//  GlyphCanvasTests
//

import CoreGraphics
import Darwin
import Foundation
import simd
import Testing
@testable import GlyphCanvas

struct GlyphCanvasTests {

    @Test func historyCheckpointRenderMatchesFullReplay() async throws {
        let store = GlyphHistoryStore()
        try await store.reset(width: 64, height: 64)
        for i in 0..<45 {
            try await store.append(Self.makeTestGlyphOperation(sequenceIndex: i))
        }
        for k in [0, 12, 44] {
            let full = try await store.renderFullPrefix(upTo: k)
            let ck = try await store.render(upTo: k)
            #expect(Self.pixelBuffersEqual(full, ck, maxChannelDelta: 2))
        }
    }

    @Test func historyTruncateKeepsPrefixAndRenders() async throws {
        let store = GlyphHistoryStore()
        try await store.reset(width: 48, height: 48)
        for i in 0..<30 {
            try await store.append(Self.makeTestGlyphOperation(sequenceIndex: i))
        }
        try await store.truncate(keepingFirst: 12)
        let opCount = await store.operationCount
        #expect(opCount == 12)
        let img = try await store.render(upTo: 12)
        #expect(img.width == 48)
        let full = try await store.renderFullPrefix(upTo: 8)
        let ck = try await store.render(upTo: 8)
        #expect(Self.pixelBuffersEqual(full, ck, maxChannelDelta: 2))
    }

    private static func makeTestGlyphOperation(sequenceIndex i: Int) -> GlyphOperation {
        let region = PixelRegion(x: 4 + (i % 5), y: 4 + (i % 4), width: 28, height: 28)
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return GlyphOperation(
            character: String(letters[i % 26]),
            position: CGPoint(
                x: CGFloat(region.x + region.width / 2),
                y: CGFloat(region.y + region.height / 2)
            ),
            fontSize: 11,
            rotationRadians: CGFloat((i % 5) * 2) * .pi / 180,
            color: RGBAColor(r: UInt8(40 + (i % 40)), g: 50, b: 60, a: 255),
            region: region,
            centerOffsetX: 0,
            centerOffsetY: 0,
            sequenceIndex: i
        )
    }

    /// `maxChannelDelta` > 0 allows tiny channel differences (anti-aliasing / checkpoint blit vs full replay).
    private static func pixelBuffersEqual(_ a: CGImage, _ b: CGImage, maxChannelDelta: UInt8 = 0) -> Bool {
        maxPixelChannelDifference(a, b).map { $0 <= Int(maxChannelDelta) } ?? false
    }

    /// Largest absolute per-channel difference (RGBA bytes); `nil` if incomparable.
    private static func maxPixelChannelDifference(_ a: CGImage, _ b: CGImage) -> Int? {
        guard a.width == b.width, a.height == b.height else { return nil }
        guard let bufa = try? ImageProcessing.makePixelBuffer(from: a),
              let bufb = try? ImageProcessing.makePixelBuffer(from: b) else { return nil }
        guard bufa.width == bufb.width, bufa.height == bufb.height,
              bufa.bytesPerRow == bufb.bytesPerRow else { return nil }
        let n = bufa.height * bufa.bytesPerRow
        var maxD = 0
        for i in 0..<n {
            let d = abs(Int(bufa.data[i]) - Int(bufb.data[i]))
            if d > maxD { maxD = d }
        }
        return maxD
    }

    @Test func earlyCoveragePhaseDivisionAndSlotBoundaries() {
        #expect(GlyphEarlyCoveragePhase.coveragePhaseEndExclusive == 2869)
        let a = GlyphEarlyCoveragePhase.coverageDivisionAndSlot(sequenceIndex: 0)
        #expect(a?.0 == 2 && a?.1 == 0)
        let b = GlyphEarlyCoveragePhase.coverageDivisionAndSlot(sequenceIndex: 3)
        #expect(b?.0 == 2 && b?.1 == 3)
        let c = GlyphEarlyCoveragePhase.coverageDivisionAndSlot(sequenceIndex: 4)
        #expect(c?.0 == 3 && c?.1 == 0)
        let d = GlyphEarlyCoveragePhase.coverageDivisionAndSlot(sequenceIndex: 2868)
        #expect(d?.0 == 20 && d?.1 == 399)
        #expect(GlyphEarlyCoveragePhase.coverageDivisionAndSlot(sequenceIndex: 2869) == nil)
    }

    @Test func earlyCoveragePhaseReferenceFontRamp() {
        let avg: CGFloat = 10
        let r0 = GlyphEarlyCoveragePhase.referenceFontSize(projectAverage: avg, sequenceIndex: 0)
        let expectedMax = avg * GlyphEarlyCoveragePhase.maxCoverageFontMultiplier
        #expect(abs(Double(r0 - expectedMax)) < 0.001)
        let rPost = GlyphEarlyCoveragePhase.referenceFontSize(projectAverage: avg, sequenceIndex: 2869)
        #expect(abs(Double(rPost - avg)) < 0.001)
        let r20Grid = GlyphEarlyCoveragePhase.referenceFontSize(projectAverage: avg, sequenceIndex: 2868)
        #expect(abs(Double(r20Grid - avg)) < 0.001)
        let rN3 = GlyphEarlyCoveragePhase.referenceFontSize(projectAverage: avg, sequenceIndex: 4)
        #expect(rN3 > avg && rN3 < r0)
    }

    @Test func regionPickWeightingPenalizesHighStampDensity() {
        let lowDensity = GlyphRegionPickWeighting.effectiveWeight(
            cellError: 100,
            stampDensity: 0,
            errorWeightPower: 1.35,
            epsilon: 0.02,
            lambdaOverlap: 0.35
        )
        let highDensity = GlyphRegionPickWeighting.effectiveWeight(
            cellError: 100,
            stampDensity: 10,
            errorWeightPower: 1.35,
            epsilon: 0.02,
            lambdaOverlap: 0.35
        )
        #expect(lowDensity > highDensity)
    }

    @Test func regionPickWeightingIncreasesWithResidualError() {
        let lowErr = GlyphRegionPickWeighting.effectiveWeight(
            cellError: 10,
            stampDensity: 1,
            errorWeightPower: 1.35,
            epsilon: 0.02,
            lambdaOverlap: 0.35
        )
        let highErr = GlyphRegionPickWeighting.effectiveWeight(
            cellError: 500,
            stampDensity: 1,
            errorWeightPower: 1.35,
            epsilon: 0.02,
            lambdaOverlap: 0.35
        )
        #expect(highErr > lowErr)
    }

    @Test func fitnessIncreasesWhenPerceptualErrorDecreases() {
        let genome = GlyphGenome(
            stamp: "A",
            fontSize: 10,
            rotationRadians: 0,
            colorR: 120,
            colorG: 120,
            colorB: 120,
            offsetX: 0,
            offsetY: 0,
            isBold: false
        )
        let hi = GlyphFitness.fitness(
            perceptualError: 200,
            genome: genome,
            lastInCell: nil,
            referenceAverageFontSize: 10
        )
        let lo = GlyphFitness.fitness(
            perceptualError: 50,
            genome: genome,
            lastInCell: nil,
            referenceAverageFontSize: 10
        )
        #expect(lo > hi)
    }

    @Test func edgeGuidedLossAlignedPrefersInkOnStrongEdges() {
        let n = 16
        let bg = RGBAColor(r: 240, g: 240, b: 240, a: 255)
        let region = PixelRegion(x: 0, y: 0, width: n, height: n)

        let edge = PixelBuffer(width: n, height: n)
        for y in 0..<n {
            for x in 0..<n {
                let o = y * edge.bytesPerRow + x * 4
                let e: UInt8 = (x >= 6 && x <= 9) ? 255 : 0
                edge.data[o] = e
                edge.data[o + 1] = 0
                edge.data[o + 2] = 0
                edge.data[o + 3] = 255
            }
        }

        let onEdge = PixelBuffer(width: n, height: n)
        for y in 0..<n {
            for x in 0..<n {
                let o = y * onEdge.bytesPerRow + x * 4
                if x >= 6 && x <= 9 {
                    onEdge.data[o] = 20
                    onEdge.data[o + 1] = 20
                    onEdge.data[o + 2] = 20
                    onEdge.data[o + 3] = 255
                } else {
                    onEdge.data[o] = bg.r
                    onEdge.data[o + 1] = bg.g
                    onEdge.data[o + 2] = bg.b
                    onEdge.data[o + 3] = 255
                }
            }
        }

        let offEdge = PixelBuffer(width: n, height: n)
        for y in 0..<n {
            for x in 0..<n {
                let o = y * offEdge.bytesPerRow + x * 4
                if x <= 3 {
                    offEdge.data[o] = 20
                    offEdge.data[o + 1] = 20
                    offEdge.data[o + 2] = 20
                    offEdge.data[o + 3] = 255
                } else {
                    offEdge.data[o] = bg.r
                    offEdge.data[o + 1] = bg.g
                    offEdge.data[o + 2] = bg.b
                    offEdge.data[o + 3] = 255
                }
            }
        }

        let lossOn = ImageProcessing.edgeGuidedLossAligned(
            candidate: onEdge,
            edgeStrength: edge,
            region: region,
            canvasBackground: bg
        )
        let lossOff = ImageProcessing.edgeGuidedLossAligned(
            candidate: offEdge,
            edgeStrength: edge,
            region: region,
            canvasBackground: bg
        )
        #expect(lossOn < lossOff)
    }

    @Test func edgeGuidedLossCropMatchesAlignedForFullRegion() {
        let n = 4
        let bg = RGBAColor(r: 250, g: 250, b: 250, a: 255)
        let region = PixelRegion(x: 0, y: 0, width: n, height: n)
        let edge = PixelBuffer(width: n, height: n)
        for y in 0..<n {
            for x in 0..<n {
                let o = y * edge.bytesPerRow + x * 4
                edge.data[o] = 0
                edge.data[o + 1] = 0
                edge.data[o + 2] = 0
                edge.data[o + 3] = 255
            }
        }
        let ex = 2
        let ey = 2
        let eo = ey * edge.bytesPerRow + ex * 4
        edge.data[eo] = 200
        edge.data[eo + 1] = 0
        edge.data[eo + 2] = 0
        edge.data[eo + 3] = 255

        let candidate = PixelBuffer(width: n, height: n)
        for y in 0..<n {
            for x in 0..<n {
                let o = y * candidate.bytesPerRow + x * 4
                candidate.data[o] = bg.r
                candidate.data[o + 1] = bg.g
                candidate.data[o + 2] = bg.b
                candidate.data[o + 3] = 255
            }
        }
        let co = ey * candidate.bytesPerRow + ex * 4
        candidate.data[co] = 10
        candidate.data[co + 1] = 10
        candidate.data[co + 2] = 10

        let aligned = ImageProcessing.edgeGuidedLossAligned(
            candidate: candidate,
            edgeStrength: edge,
            region: region,
            canvasBackground: bg
        )
        let crop = ImageProcessing.edgeGuidedLoss(
            candidate: candidate,
            edgeStrength: edge,
            region: region,
            canvasBackground: bg
        )
        #expect(abs(aligned - crop) < 1e-9)
    }

    @Test func urlImportNormalizesBareHostToHTTPS() {
        let u = URLImageImportHelpers.normalizedHTTPURL(from: "example.com/foo")
        #expect(u?.scheme == "https")
        #expect(u?.host == "example.com")
        #expect(u?.path == "/foo")
    }

    @Test func urlImportPreservesExplicitScheme() {
        let u = URLImageImportHelpers.normalizedHTTPURL(from: "http://example.com")
        #expect(u?.scheme == "http")
    }

    @Test func urlImportRejectsEmptyInput() {
        #expect(URLImageImportHelpers.normalizedHTTPURL(from: "") == nil)
        #expect(URLImageImportHelpers.normalizedHTTPURL(from: "   ") == nil)
    }

    @Test func urlImportAllowsOnlyHTTPOrHTTPS() {
        #expect(URLImageImportHelpers.isAllowedHTTPURL(URL(string: "https://a")!))
        #expect(URLImageImportHelpers.isAllowedHTTPURL(URL(string: "http://a")!))
        #expect(!URLImageImportHelpers.isAllowedHTTPURL(URL(string: "file:///tmp/x")!))
    }

    @Test func urlImportResolvesRelativeAndDedupes() {
        let base = URL(string: "https://example.org/dir/page.html")!
        let out = URLImageImportHelpers.resolvedHTTPSURLs(
            strings: [
                "//cdn.example.com/a.png",
                "https://cdn.example.com/a.png",
                "b.jpg",
                "ftp://ignore.me/x.png",
            ],
            baseURL: base
        )
        #expect(out.count == 2)
        #expect(out[0].absoluteString == "https://cdn.example.com/a.png")
        #expect(out[1].absoluteString == "https://example.org/dir/b.jpg")
    }

    @Test func urlImportSniffsHTMLPrefix() {
        let data = Data("<!DOCTYPE html><html>".utf8)
        #expect(URLImageImportHelpers.sniffsHTML(data))
        #expect(!URLImageImportHelpers.sniffsHTML(Data([0xFF, 0xD8])))
    }

    @Test func crossoverIsDeterministicForFixedRNG() {
        let a = GlyphGenome(
            stamp: "A",
            fontSize: 11,
            rotationRadians: 0.2,
            colorR: 10,
            colorG: 20,
            colorB: 30,
            offsetX: 1,
            offsetY: -1,
            isBold: false
        )
        let b = GlyphGenome(
            stamp: "Z",
            fontSize: 13,
            rotationRadians: -0.4,
            colorR: 100,
            colorG: 110,
            colorB: 120,
            offsetX: 2,
            offsetY: 2,
            isBold: false
        )
        var rng1 = LCG64(state: 0xC0FFEE)
        var rng2 = LCG64(state: 0xC0FFEE)
        let c1 = GlyphGenome.crossover(a, b, rng: &rng1)
        let c2 = GlyphGenome.crossover(a, b, rng: &rng2)
        #expect(c1 == c2)
    }

    @Test func artworkManifestJSONRoundTripPreservesOperations() throws {
        let op = Self.makeTestGlyphOperation(sequenceIndex: 3)
        let manifest = ArtworkManifest(
            canvasWidth: 64,
            canvasHeight: 48,
            operations: [op],
            titlePrefix: "Paris — Apr 2024"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(ArtworkManifest.self, from: data)
        #expect(decoded == manifest)
        #expect(decoded.operations == [op])
        #expect(decoded.titlePrefix == "Paris — Apr 2024")
    }

    @Test func glyphOperationJSONRoundTrip() throws {
        let op = Self.makeTestGlyphOperation(sequenceIndex: 7)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(op)
        let decoded = try decoder.decode(GlyphOperation.self, from: data)
        #expect(decoded == op)
    }

    @Test func darkestAmongTopFiveCommonColorsPicksDarkestOfFrequentBuckets() throws {
        let w = 64
        let h = 64
        guard let ctx = ImageProcessing.makeContext(width: w, height: h, data: nil) else {
            Issue.record("Could not create bitmap context")
            return
        }
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h / 2)))
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: CGFloat(h / 2), width: CGFloat(w), height: CGFloat(h / 2)))
        guard let img = ctx.makeImage() else {
            Issue.record("Could not make CGImage")
            return
        }
        let c = try ImageProcessing.darkestAmongTopFiveCommonColors(from: img)
        let lum =
            PerceptualScoring.redWeight * Double(c.r)
            + PerceptualScoring.greenWeight * Double(c.g)
            + PerceptualScoring.blueWeight * Double(c.b)
        #expect(lum < 80)
    }

    @Test func historyImportOperationsMatchesIncrementalAppends() async throws {
        let w = 32
        let h = 32
        var ops: [GlyphOperation] = []
        for i in 0..<50 {
            ops.append(Self.makeTestGlyphOperation(sequenceIndex: i))
        }

        let incremental = GlyphHistoryStore()
        try await incremental.reset(width: w, height: h)
        for op in ops {
            try await incremental.append(op)
        }

        let bulk = GlyphHistoryStore()
        try await bulk.importOperations(ops, width: w, height: h)

        let n = ops.count
        let incOps = await incremental.copyOperations()
        let bulkOps = await bulk.copyOperations()
        #expect(incOps == bulkOps)

        let imgInc = try await incremental.render(upTo: n)
        let imgBulk = try await bulk.render(upTo: n)
        #expect(Self.pixelBuffersEqual(imgInc, imgBulk))
    }

    @Test func evolutionPreservesEvaluationBudgetAndFindsBest() {
        let region = PixelRegion(x: 0, y: 0, width: 16, height: 16)
        let config = GeneticEvolutionConfig(
            populationSize: 8,
            generations: 3,
            eliteFraction: 0.3,
            maxEvaluations: 64
        )
        let pool: [String] = ["A", "B", "C", "D", "E", "F", "G", "H"]
        let result = GlyphEvolutionEngine.evolve(
            config: config,
            seedFromCache: nil,
            region: region,
            meanLuminanceY: 128,
            averageFontSize: 10,
            baseRGB: SIMD3<Float>(128, 128, 128),
            stampPool: pool,
            evaluateFitness: { g in
                Double(g.stamp.unicodeScalars.first?.value ?? 0)
            },
            shouldCancel: { false }
        )
        #expect(result.evaluationsUsed == 24)
        #expect(result.generationsRun == 3)
        #expect(result.bestGenome != nil)
    }

    @Test func colorFidelityMapsToExpectedQuantizationStep() {
        #expect(ImageProcessing.colorQuantizationStep(forFidelity: 8) == 1)
        #expect(ImageProcessing.colorQuantizationStep(forFidelity: 7) == 2)
        #expect(ImageProcessing.colorQuantizationStep(forFidelity: 4) == 16)
        #expect(ImageProcessing.colorQuantizationStep(forFidelity: 1) == 128)
    }

    @Test func quantizeRGBUsesBucketCenters() {
        let inColor = RGBAColor(r: 100, g: 201, b: 3, a: 255)
        let q = ImageProcessing.quantizeRGB(inColor, step: 64)
        #expect(q.r == 96)
        #expect(q.g == 224)
        #expect(q.b == 32)
    }

    @Test func glyphGenomeRandomQuantizesChannelsWhenStepIsCoarse() {
        var rng = LCG64(state: 0x1234ABCD)
        let g = GlyphGenome.random(
            region: PixelRegion(x: 0, y: 0, width: 12, height: 12),
            meanLuminanceY: 120,
            averageFontSize: 10,
            baseRGB: SIMD3<Float>(127, 127, 127),
            colorQuantizationStep: 64,
            stampPool: ["A", "B", "C"],
            isBold: false,
            rng: &rng
        )
        #expect(Int(g.colorR.rounded()) % 64 == 32)
        #expect(Int(g.colorG.rounded()) % 64 == 32)
        #expect(Int(g.colorB.rounded()) % 64 == 32)
    }

    @Test func stampSetCharacterModeProducesOrderedUniqueStrings() {
        let s = StampSetPipeline.filteredOrderedUniqueCharacters(from: "aba", mode: .both)
        #expect(s == ["a", "b"])
    }

    @Test func stampSetWordModeKeepsApostropheAndStripsEdgePunctuation() {
        let text = "  (Hello,)  world…  don't  "
        let words = StampSetPipeline.filteredOrderedUniqueWords(from: text, mode: .both)
        #expect(words == ["Hello", "world", "don't"])
    }

    @Test func stampSetWordModeUppercaseCollapsesDuplicates() {
        let text = "hello Hello"
        let words = StampSetPipeline.filteredOrderedUniqueWords(from: text, mode: .uppercase)
        #expect(words == ["HELLO"])
    }

    @Test func stampSetActiveSetFallsBackWhenWordInputEmpty() {
        let active = StampSetPipeline.activeSet(base: "   ", mode: .both, source: .words)
        #expect(!active.isEmpty)
    }

    @Test func predefinedStampMergeAppendsMissingOnly() {
        var base = "AB"
        PredefinedStampSets.mergeAppendingUnique(into: &base, preset: "BC")
        #expect(base == "ABC")
    }

    @Test func importRotationQuarterTurnSwapsDimensions() {
        let base = Self.solidTestCGImage(width: 20, height: 30)
        let once = ImageProcessing.cgImageRotatedQuarterTurns(base, quarterTurns: 1)
        #expect(once?.width == 30)
        #expect(once?.height == 20)
        let four = ImageProcessing.cgImageRotatedQuarterTurns(base, quarterTurns: 4)
        #expect(four?.width == base.width)
        #expect(four?.height == base.height)
    }

    @Test func importCropNormalizedTopLeftHalvesDimensions() {
        let base = Self.solidTestCGImage(width: 100, height: 80)
        let cropped = ImageProcessing.cgImageCroppingNormalizedTopLeft(
            base,
            normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        )
        #expect(cropped?.width == 50)
        #expect(cropped?.height == 40)
    }

    private static func solidTestCGImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard
            let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        else {
            preconditionFailure("CGContext")
        }
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cg = ctx.makeImage() else {
            preconditionFailure("CGImage")
        }
        return cg
    }
}

// MARK: - Test RNG

private struct LCG64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
