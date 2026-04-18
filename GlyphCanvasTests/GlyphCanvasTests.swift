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
            character: "A",
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
            character: "A",
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
            character: "Z",
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
            operations: [op]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(ArtworkManifest.self, from: data)
        #expect(decoded == manifest)
        #expect(decoded.operations == [op])
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
        let pool: [Character] = Array("ABCDEFGH")
        let result = GlyphEvolutionEngine.evolve(
            config: config,
            seedFromCache: nil,
            region: region,
            meanLuminanceY: 128,
            averageFontSize: 10,
            baseRGB: SIMD3<Float>(128, 128, 128),
            characterPool: pool,
            evaluateFitness: { g in
                Double(g.character.unicodeScalars.first?.value ?? 0)
            },
            shouldCancel: { false }
        )
        #expect(result.evaluationsUsed == 24)
        #expect(result.generationsRun == 3)
        #expect(result.bestGenome != nil)
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
