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

    @Test func captionWordsGroupIntoLinesOnPausesAndLength() {
        let words = [
            CaptionWord(text: "hello", start: 0, end: 0.4),
            CaptionWord(text: "there", start: 0.5, end: 0.9),
            CaptionWord(text: "after", start: 3, end: 3.3),
            CaptionWord(text: String(repeating: "x", count: 30), start: 3.4, end: 4)
        ]
        let lines = CaptionTranscriber.lines(from: words)
        #expect(lines.map(\.text) == ["hello there", "after", String(repeating: "x", count: 30)])
        #expect(lines[0].start == 0 && lines[0].end == 0.9)
        #expect(CaptionLayout.activeIndex(in: lines, at: 1.2) == 0)
        #expect(CaptionLayout.activeIndex(in: lines, at: 2) == nil)
        #expect(CaptionLayout.opacity(of: lines[0], at: 0) == 0)
        #expect(CaptionLayout.opacity(of: lines[0], at: 0.5) == 1)
        #expect(CaptionLayout.opacity(of: lines[0], at: 1.5) == 0)
    }

    @Test func captionLayoutIsSolidAtBottomEmptyAboveHalfAndMostlyUpright() {
        let size = CGSize(width: 1280, height: 720)
        let words = CaptionLayout.placements(text: "the quick brown fox jumps", size: size, seed: 3)
        #expect(!words.isEmpty)
        #expect(words.allSatisfy { $0.center.y < size.height * 0.5 })
        let band = words.filter { $0.center.y < size.height * 0.1 }
        let upper = words.filter { $0.center.y >= size.height * 0.3 }
        #expect(band.count > upper.count * 2, "density should fall off with height")
        // Bottom rows tile the full width with no gaps wider than a space.
        let firstRow = band.filter { abs($0.center.y - band[0].center.y) < 1 }.sorted { $0.center.x < $1.center.x }
        #expect(firstRow.first!.center.x < 80 && firstRow.last!.center.x > size.width - 120)
        #expect(words.allSatisfy { abs($0.rotation) <= 0.6 })
        let tilted = words.filter { abs($0.rotation) > 0.35 }
        #expect(Double(tilted.count) < Double(words.count) * 0.1)
        #expect(CaptionLayout.placements(text: "the quick brown fox jumps", size: size, seed: 3) == words, "layout must be stable per line")
    }

    @Test func revealStylesSettleAtRestAndStartVisiblyDifferent() {
        for style in GlyphRevealStyle.animated {
            let end = GlyphRevealMath.pose(style, t: 1, seed: 7)
            #expect(end.opacity < 0.01, "\(style) should fade out to hand off to the committed glyph")
            #expect(abs(end.scale - 1) < 0.05 && abs(end.scaleY - 1) < 0.05, "\(style) should end at its committed size")
            #expect(abs(end.offset.width) < 0.05 && abs(end.offset.height) < 0.05, "\(style) should end at its committed position")
        }
    }

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

    @Test func encodingSessionSnapshotDetectsUnchangedConfig() {
        let baseline = Self.makeEncodingSnapshot()
        let same = Self.makeEncodingSnapshot()
        #expect(baseline == same)
    }

    @Test func encodingSessionSnapshotDetectsStampTextChange() {
        let baseline = Self.makeEncodingSnapshot(stampFingerprint: "a\u{1F}b")
        let changed = Self.makeEncodingSnapshot(stampFingerprint: "a\u{1F}c")
        #expect(baseline != changed)
    }

    @Test func encodingSessionSnapshotDetectsIterationsPerSecondChange() {
        let baseline = Self.makeEncodingSnapshot(iterationsPerSecond: 120)
        let changed = Self.makeEncodingSnapshot(iterationsPerSecond: 150)
        #expect(baseline != changed)
    }

    @Test func liveRegenerationIgnoresSpeedButNotLook() {
        let base = Self.makeEncodingSnapshot()
        #expect(base.ignoringSpeed == Self.makeEncodingSnapshot(iterationsPerSecond: 280).ignoringSpeed)
        #expect(base.ignoringSpeed != Self.makeEncodingSnapshot(regionSize: 20).ignoringSpeed)
        #expect(base.ignoringSpeed != Self.makeEncodingSnapshot(encodingComparisonMode: .edges).ignoringSpeed)
    }

    /// Changing an output setting mid-encode must redraw from a blank canvas (history resets, then regrows).
    @MainActor
    @Test func changingDetailRedrawsFromScratch() async throws {
        let vm = AppViewModel()
        vm.loadImage(try Self.makeGradientImage(side: 96))
        try await Self.waitUntil { vm.glyphCount >= 40 }
        let before = vm.glyphCount
        vm.regionSize = vm.regionSize == 20 ? 6 : 20
        try await Self.waitUntil { vm.glyphCount < before && vm.glyphHistory.count == vm.glyphCount }
        await vm.pause()
    }

    @MainActor
    private static func waitUntil(timeout: Double = 8, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                Issue.record("Timed out waiting for condition")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private static func makeGradientImage(side: Int) throws -> CGImage {
        let ctx = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        for x in 0..<side {
            ctx.setFillColor(red: CGFloat(x) / CGFloat(side), green: 0.3, blue: 1 - CGFloat(x) / CGFloat(side), alpha: 1)
            ctx.fill(CGRect(x: x, y: 0, width: 1, height: side))
        }
        return try #require(ctx.makeImage())
    }

    @Test func encodingSessionSnapshotIgnoresPlaybackOnlyFields() {
        // Snapshots exclude playbackGlyphsPerSecond; two snapshots with identical encoding fields match.
        let a = Self.makeEncodingSnapshot()
        let b = Self.makeEncodingSnapshot()
        #expect(a == b)
    }

    @Test func encodingSessionSnapshotStampFingerprintDiffersByMode() {
        let chars = EncodingSessionSnapshot.stampFingerprint(for: ["hello", "world"])
        let words = EncodingSessionSnapshot.stampFingerprint(for: ["hello world"])
        #expect(chars != words)
    }

    private static func makeEncodingSnapshot(
        stampFingerprint: String = EncodingSessionSnapshot.stampFingerprint(for: ["A", "B", "C"]),
        stampSourceMode: StampSourceMode = .characters,
        characterCaseMode: CharacterCaseMode = .both,
        iterationsPerSecond: Double = 120,
        averageFontSize: Double = 10,
        colorFidelity: Double = 8,
        regionSize: Double = 12,
        candidateCount: Double = 6,
        optimizationMode: OptimizationMode = .greedy,
        encodingComparisonMode: EncodingComparisonMode = .perceptual,
        geneticPopulation: Double = 16,
        geneticGenerations: Double = 8,
        geneticMaxEvaluations: Double = 128
    ) -> EncodingSessionSnapshot {
        EncodingSessionSnapshot(
            stampFingerprint: stampFingerprint,
            stampSourceMode: stampSourceMode,
            characterCaseMode: characterCaseMode,
            iterationsPerSecond: iterationsPerSecond,
            averageFontSize: averageFontSize,
            colorFidelity: colorFidelity,
            regionSize: regionSize,
            candidateCount: candidateCount,
            optimizationMode: optimizationMode,
            encodingComparisonMode: encodingComparisonMode,
            geneticPopulation: geneticPopulation,
            geneticGenerations: geneticGenerations,
            geneticMaxEvaluations: geneticMaxEvaluations
        )
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

    @Test func fitnessPenalizesQuarterTurnsVersusUpright() {
        let pe = 100.0
        let upright = GlyphGenome(
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
        let quarter = GlyphGenome(
            stamp: "A",
            fontSize: 10,
            rotationRadians: .pi / 2,
            colorR: 120,
            colorG: 120,
            colorB: 120,
            offsetX: 0,
            offsetY: 0,
            isBold: false
        )
        let negQuarter = GlyphGenome(
            stamp: "A",
            fontSize: 10,
            rotationRadians: -.pi / 2,
            colorR: 120,
            colorG: 120,
            colorB: 120,
            offsetX: 0,
            offsetY: 0,
            isBold: false
        )
        let f0 = GlyphFitness.fitness(
            perceptualError: pe,
            genome: upright,
            lastInCell: nil,
            referenceAverageFontSize: 10
        )
        let f90 = GlyphFitness.fitness(
            perceptualError: pe,
            genome: quarter,
            lastInCell: nil,
            referenceAverageFontSize: 10
        )
        let fNeg90 = GlyphFitness.fitness(
            perceptualError: pe,
            genome: negQuarter,
            lastInCell: nil,
            referenceAverageFontSize: 10
        )
        #expect(f0 > f90)
        #expect(f0 > fNeg90)
    }

    @Test func fitnessPenalizesDiagonalVersusUprightAtSamePerceptualError() {
        let pe = 100.0
        let upright = GlyphGenome(
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
        let diagonal = GlyphGenome(
            stamp: "A",
            fontSize: 10,
            rotationRadians: .pi / 4,
            colorR: 120,
            colorG: 120,
            colorB: 120,
            offsetX: 0,
            offsetY: 0,
            isBold: false
        )
        let f0 = GlyphFitness.fitness(
            perceptualError: pe,
            genome: upright,
            lastInCell: nil,
            referenceAverageFontSize: 10
        )
        let f45 = GlyphFitness.fitness(
            perceptualError: pe,
            genome: diagonal,
            lastInCell: nil,
            referenceAverageFontSize: 10
        )
        #expect(f0 > f45)
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

    @Test func recentStampSetStoreRoundTripSerialization() {
        let seed = RecentStampSet(
            id: "characters::A\u{1F}B",
            fingerprint: "characters::A\u{1F}B",
            sourceMode: .characters,
            rawInput: "AB",
            displayLabel: "AB",
            stampCount: 2,
            updatedAt: Date(timeIntervalSince1970: 1234)
        )
        let json = RecentStampSetStore.encode([seed])
        let decoded = RecentStampSetStore.decode(from: json)
        #expect(decoded.count == 1)
        #expect(decoded.first?.fingerprint == seed.fingerprint)
        #expect(decoded.first?.sourceMode == seed.sourceMode)
        #expect(decoded.first?.rawInput == seed.rawInput)
        #expect(decoded.first?.stampCount == seed.stampCount)
    }

    @Test func recentStampSetStoreUpsertDedupesAndMovesToFront() {
        let now = Date(timeIntervalSince1970: 100)
        let first = RecentStampSetStore.makeRecent(
            base: "ABC",
            mode: .both,
            source: .characters,
            now: now
        )!
        let second = RecentStampSetStore.makeRecent(
            base: "hello world",
            mode: .both,
            source: .words,
            now: Date(timeIntervalSince1970: 200)
        )!
        let replacedFirst = RecentStampSetStore.makeRecent(
            base: "CBAA",
            mode: .both,
            source: .characters,
            now: Date(timeIntervalSince1970: 300)
        )!

        let list1 = RecentStampSetStore.upsert(first, into: [])
        let list2 = RecentStampSetStore.upsert(second, into: list1)
        let list3 = RecentStampSetStore.upsert(replacedFirst, into: list2)

        #expect(list3.count == 2)
        #expect(list3[0].fingerprint == first.fingerprint)
        #expect(list3[1].fingerprint == second.fingerprint)
        #expect(list3[0].rawInput == "CBAA")
    }

    @Test func recentStampSetStoreTrimsToCapacity() {
        var items: [RecentStampSet] = []
        for i in 0..<12 {
            let entry = RecentStampSetStore.makeRecent(
                base: "item\(i)",
                mode: .both,
                source: .words,
                now: Date(timeIntervalSince1970: TimeInterval(i))
            )!
            items = RecentStampSetStore.upsert(entry, into: items)
        }
        #expect(items.count == RecentStampSetStore.maxItems)
        #expect(items.first?.rawInput == "item11")
        #expect(items.last?.rawInput == "item2")
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

// MARK: - Video transition

import AVFoundation

@MainActor
struct VideoTransitionTests {
    @Test func pacingIsMonotonicAndInvertible() {
        let total = 400
        var last = -1.0
        for step in 0...100 {
            let r = GlyphTransitionPacing.revealed(at: Double(step) / 50, total: total, start: 0.5, cut: 1.5)
            #expect(r >= last)
            last = r
        }
        #expect(last == Double(total))
        for i in [0, 10, 199, 399] {
            let b = GlyphTransitionPacing.birth(of: i, total: total, start: 0.5, cut: 1.5)
            #expect(abs(GlyphTransitionPacing.revealed(at: b, total: total, start: 0.5, cut: 1.5) - Double(i + 1)) < 1e-6)
        }
    }

    @Test func editClampKeepsCutInsideClipOne() {
        var e = TransitionEdit(clip1Duration: 4, clip2Duration: 3)
        e.clip1In = 3.5
        e.cut = 10
        e.transitionStart = 20
        e.clip2Out = 1
        e.clip2In = 2
        e.clamp()
        #expect(e.cut <= e.clip1Available + 1e-9)
        #expect(e.transitionStart < e.cut)
        #expect(e.clip2Out > e.clip2In)
        #expect(e.outputDuration == e.cut + e.clip2Length)
    }

    /// Red clip → green clip: before the build it's red, mid-build red with green-ish glyphs, after the cut green.
    @Test func exportRendersGlyphBuildThenCutsToClipTwo() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "glyph-transition-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let red = try await Self.makeSolidVideo(at: dir.appending(path: "red.mov"), rgb: (230, 20, 20), seconds: 3)
        let green = try await Self.makeSolidVideo(at: dir.appending(path: "green.mov"), rgb: (20, 200, 40), seconds: 2)

        let s1 = try await TransitionSource.load(red)
        let s2 = try await TransitionSource.load(green)
        var edit = TransitionEdit(clip1Duration: s1.duration, clip2Duration: s2.duration)
        edit.transitionStart = 0.5
        edit.cut = 1.5
        edit.coverage = 0.6
        edit.clamp()

        let frame = try await TransitionComposer.planningFrame(of: s2, at: 0, renderSize: s1.renderSize)
        let plan = try await TransitionComposer.makePlan(frame: frame, coverage: edit.coverage) { _ in }
        #expect(plan.ops.count >= 300)

        let built = try TransitionComposer.build(edit: edit, clip1: s1, clip2: s2, style: .pop, plan: plan)
        let session = try #require(AVAssetExportSession(asset: built.composition, presetName: AVAssetExportPresetHighestQuality))
        session.videoComposition = built.videoComposition
        session.audioMix = built.audioMix
        let out = dir.appending(path: "out.mp4")
        try await session.export(to: out, as: .mp4)

        let result = AVURLAsset(url: out)
        let duration = try await result.load(.duration).seconds
        #expect(abs(duration - edit.outputDuration) < 0.1)

        let gen = AVAssetImageGenerator(asset: result)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        func greenShare(at t: Double) async throws -> Double {
            let (img, _) = try await gen.image(at: CMTime(seconds: t, preferredTimescale: 600))
            let (r, g) = Self.meanRG(img)
            return g / max(1, r + g)
        }
        let before = try await greenShare(at: 0.2)
        let during = try await greenShare(at: 1.45)
        let after = try await greenShare(at: 2.5)
        #expect(before < 0.15)
        #expect(during > before + 0.15, "glyphs of clip 2 should be visible over clip 1 near the cut")
        #expect(after > 0.8)
    }

    static func meanRG(_ image: CGImage) -> (Double, Double) {
        let w = 32, h = 32
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var r = 0.0, g = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            r += Double(px[i])
            g += Double(px[i + 1])
        }
        return (r / Double(w * h), g / Double(w * h))
    }

    static func makeSolidVideo(at url: URL, rgb: (UInt8, UInt8, UInt8), seconds: Int) async throws -> URL {
        let w = 320, h = 240, fps: Int32 = 30
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for f in 0..<(seconds * Int(fps)) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let pb = try #require(buffer)
            CVPixelBufferLockBaseAddress(pb, [])
            let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
            let bpr = CVPixelBufferGetBytesPerRow(pb)
            for y in 0..<h {
                for x in 0..<w {
                    let p = base + y * bpr + x * 4
                    p[0] = rgb.2; p[1] = rgb.1; p[2] = rgb.0; p[3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }
}
