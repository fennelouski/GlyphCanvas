//
//  AppViewModel.swift
//  GlyphCanvas
//
//  Created by Codex on 4/16/26.
//

import Combine
import CoreGraphics
import Foundation
import simd

#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

@MainActor
final class AppViewModel: ObservableObject {
    @Published var displayImage: CGImage?
    /// Downscaled source used for optimization (same dimensions as canvas).
    @Published var sourceImageForOverlay: CGImage?
    @Published var isRunning = false
    @Published var iterationCount = 0
    @Published var glyphCount = 0

    /// Operation-based timeline (mirrors `GlyphHistoryStore`; append-only during generation at live edge).
    @Published var glyphHistory: [GlyphOperation] = []
    /// How many glyphs are visible: `0...glyphHistory.count` (live edge when equal to count).
    @Published var playbackIndex: Int = 0
    @Published var isPlayingBack = false
    @Published var isStopped = false
    /// Glyphs advanced per second during timeline playback.
    @Published var playbackGlyphsPerSecond: Double = 24

    /// End of committed history (same as `glyphHistory.count` when in sync).
    var liveGenerationIndex: Int { glyphHistory.count }

    /// Target rate from the slider (upper bound for scheduling).
    @Published var iterationsPerSecond: Double = 120
    /// Measured iterations completed per second (rolling).
    @Published var measuredIterationsPerSecond: Double = 0

    @Published var regionSize: Double = 12
    @Published var candidateCount: Double = 6
    @Published var averageFontSize: Double = 10

    @Published var optimizationMode: OptimizationMode = .greedy
    @Published var encodingComparisonMode: EncodingComparisonMode = .perceptual
    /// 1...8 where 8 keeps near-original color fidelity (minimal quantization).
    @Published var colorFidelity: Double = 8
    /// Genetic mode: population size (12…24).
    @Published var geneticPopulation: Double = 16
    /// Genetic mode: generations per region (5…15), capped by max evaluations.
    @Published var geneticGenerations: Double = 8
    @Published var geneticMaxEvaluations: Double = 128

    @Published var debugOptimizationOverlay = false
    /// Total loss for the last step (perceptual + penalties where applicable); aligns with progress EMA. Lower is better.
    @Published var debugLastStepLoss: Double?
    @Published var debugLastFitness: Double?
    @Published var debugLastGeneration: Int?
    @Published var debugLastEvaluations: Int?
    @Published var debugLastRegion: PixelRegion?

    /// 0…1 rough progress from rolling perceptual score vs initial reference.
    @Published var progressEstimate: Double = 0
    @Published var showSourceOverlay = false
    /// When true, the optimization loop skips live canvas snapshots (e.g. scene backgrounded).
    @Published var suppressLiveDisplayUpdates = false

    @Published var exportMessage: String?

    /// Gallery row id for this studio session; cleared on new source image, set when restoring from gallery or after first save.
    private(set) var activeArtworkID: UUID?

    /// Human-readable title prefix from import metadata (date, place); combined with `GalleryArchiveNaming` on save.
    private(set) var pendingImportTitlePrefix: String?

    /// Set from `EditorView` so encoding can archive to the shared `ArtworkLibrary` without reaching for environment objects.
    var galleryLibrary: ArtworkLibrary?

    /// User-editable pool; persisted via `@AppStorage` in `ContentView` (keys in `GlyphCanvasStorageKey`).
    @Published var baseCharacterSet: String = GlyphCanvasCharacterSetDefaults.baseString
    @Published var stampSourceMode: StampSourceMode = .characters
    @Published var characterCaseMode: CharacterCaseMode = .both

    /// Filtered, de-duplicated stamps (single characters, emoji, or words) used for glyph sampling.
    /// Character mode: letters filtered by `characterCaseMode`; non-letters kept; internal spaces kept.
    /// Word mode: unique words from pasted text (see `StampSetPipeline`). Empty input falls back to defaults.
    var activeStamps: [String] {
        StampSetPipeline.activeSet(
            base: baseCharacterSet,
            mode: characterCaseMode,
            source: stampSourceMode
        )
    }

    /// Shown when user input would yield no stamps before fallback to defaults.
    var showsCharacterSetFallbackNotice: Bool {
        StampSetPipeline.isEffectivelyEmpty(
            base: baseCharacterSet,
            mode: characterCaseMode,
            source: stampSourceMode
        )
    }

    var hasLoadedImage: Bool { engine != nil }

    fileprivate var engine: GlyphRenderEngine?
    fileprivate var optimizationTask: Task<Void, Never>?
    fileprivate let historyStore = GlyphHistoryStore()
    fileprivate var playbackTask: Task<Void, Never>?
    /// When true, timeline playback wraps from the end back to the start (gallery fullscreen).
    fileprivate var playbackLoops = false

    fileprivate var scoreEMA: Double?
    fileprivate var referenceError: Double?
    /// After the user stops encoding via the Studio Stop control, skip auto-start until they press Play or load/reset.
    fileprivate var encodingAutostartSuppressed = false

    private var importTitleRefinementGeneration: UInt = 0
    private var importGeocodeTask: Task<Void, Never>?
}

extension AppViewModel {
    func applyStudioParameterDefaults() {
        regionSize = 12
        iterationsPerSecond = 120
        averageFontSize = 10
        candidateCount = 6
        playbackGlyphsPerSecond = 24
        geneticPopulation = 16
        geneticGenerations = 8
        geneticMaxEvaluations = 128
        colorFidelity = 8
    }

    /// Applies standard vs high-detail engine presets from `UserDefaults` (see `GlyphCanvasStorageKey`).
    func applyStudioPresetFromSettings() {
        if GlyphCanvasStorageKey.highDetailModeEnabled() {
            applyStudioParameterDefaults()
            regionSize = 8
            candidateCount = 10
            averageFontSize = 8.5
            iterationsPerSecond = 150
            geneticPopulation = 18
            geneticGenerations = 10
            geneticMaxEvaluations = 192
        } else {
            applyStudioParameterDefaults()
        }
    }

    func loadImage(_ image: CGImage, hints: ImportHints? = nil) {
        importGeocodeTask?.cancel()
        importGeocodeTask = nil
        importTitleRefinementGeneration += 1
        let refinementGen = importTitleRefinementGeneration
        let titleSnapshot = ImportTitleBuilder.provisionalPrefixAndLocation(hints: hints)
        pendingImportTitlePrefix = titleSnapshot.prefix

        if let loc = titleSnapshot.location {
            let capDate = titleSnapshot.captureDate
            importGeocodeTask = Task { [weak self] in
                guard let place = await ImportGeocoding.placeLabel(for: loc) else { return }
                let merged = ImportTitleBuilder.prefix(placeName: place, captureDate: capDate) ?? place
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard refinementGen == self.importTitleRefinementGeneration else { return }
                    self.pendingImportTitlePrefix = merged
                    if let aid = self.activeArtworkID, let lib = self.galleryLibrary {
                        try? lib.updateTitlePrefix(id: aid, titlePrefix: merged)
                    }
                }
            }
        }

        Task {
            await pauseAndAwaitTask()
            do {
                let downscaled = try ImageProcessing.downscaledImage(image, maxDimension: 512)
                let canvasBG =
                    (try? ImageProcessing.darkestAmongTopFiveCommonColors(from: downscaled))
                    ?? RGBAColor(r: 255, g: 255, b: 255, a: 255)
                try await historyStore.reset(width: downscaled.width, height: downscaled.height, canvasBackground: canvasBG)
                let encMode = await MainActor.run { self.encodingComparisonMode }
                let engine = try GlyphRenderEngine(
                    target: downscaled,
                    canvasBackground: canvasBG,
                    initialEncodingComparisonMode: encMode
                )
                let snapshot = try engine.snapshot()
                await MainActor.run {
                    self.sourceImageForOverlay = downscaled
                    self.engine = engine
                    self.displayImage = snapshot
                    self.iterationCount = 0
                    self.glyphCount = 0
                    self.glyphHistory = []
                    self.playbackIndex = 0
                    self.isPlayingBack = false
                    self.isStopped = false
                    self.playbackTask?.cancel()
                    self.playbackTask = nil
                    self.scoreEMA = nil
                    self.referenceError = nil
                    self.progressEstimate = 0
                    self.measuredIterationsPerSecond = 0
                    self.clearOptimizationDebug()
                    self.applyStudioPresetFromSettings()
                    self.activeArtworkID = nil
                    self.encodingAutostartSuppressed = false
                    self.attemptEncodingAutostartIfEligible()
                }
            } catch {
                await MainActor.run {
                    self.sourceImageForOverlay = nil
                    self.engine = nil
                    self.displayImage = nil
                    self.iterationCount = 0
                    self.glyphCount = 0
                    self.glyphHistory = []
                    self.playbackIndex = 0
                    self.activeArtworkID = nil
                    self.pendingImportTitlePrefix = nil
                }
            }
        }
    }

    func start() {
        guard !isRunning, engine != nil, playbackIndex == glyphHistory.count else { return }
        encodingAutostartSuppressed = false
        if let library = galleryLibrary {
            performPersistArtworkToLibrary(
                library: library,
                userInitiated: false,
                bumpCreatedAt: false,
                successMessage: nil
            )
        }
        isRunning = true
        optimizationTask = Task.detached(priority: .userInitiated) { [weak self] in
            await runGlyphOptimizationLoop(weakViewModel: self)
        }
    }

    /// Auto-starts encoding for a fresh canvas (empty history) unless the user suppressed it with Stop.
    func attemptEncodingAutostartIfEligible() {
        guard hasLoadedImage,
              !isRunning,
              playbackIndex == glyphHistory.count,
              glyphHistory.isEmpty,
              !encodingAutostartSuppressed
        else { return }
        start()
    }

    func pause() async {
        let task = optimizationTask
        optimizationTask = nil
        isRunning = false
        task?.cancel()
        if let task {
            await task.value
        }
    }

    func pauseEncodingAndSuppressAutostart() async {
        await pause()
        encodingAutostartSuppressed = true
    }

    func reset() {
        Task {
            await pauseAndAwaitTask()
            do {
                let src = await MainActor.run { self.sourceImageForOverlay }
                guard let src else { return }
                let canvasBG =
                    (try? ImageProcessing.darkestAmongTopFiveCommonColors(from: src))
                    ?? RGBAColor(r: 255, g: 255, b: 255, a: 255)
                try await historyStore.reset(width: src.width, height: src.height, canvasBackground: canvasBG)
                await MainActor.run {
                    let encMode = self.encodingComparisonMode
                    guard let engine = try? GlyphRenderEngine(
                        target: src,
                        canvasBackground: canvasBG,
                        initialEncodingComparisonMode: encMode
                    ),
                          let snap = try? engine.snapshot() else {
                        self.engine = nil
                        self.displayImage = nil
                        return
                    }
                    self.engine = engine
                    self.displayImage = snap
                    self.iterationCount = 0
                    self.glyphCount = 0
                    self.glyphHistory = []
                    self.playbackIndex = 0
                    self.isPlayingBack = false
                    self.isStopped = false
                    self.playbackTask?.cancel()
                    self.playbackTask = nil
                    self.scoreEMA = nil
                    self.referenceError = nil
                    self.progressEstimate = 0
                    self.clearOptimizationDebug()
                    self.applyStudioPresetFromSettings()
                    self.encodingAutostartSuppressed = false
                    self.attemptEncodingAutostartIfEligible()
                }
            } catch {
                await MainActor.run {
                    self.glyphHistory = []
                    self.playbackIndex = 0
                }
            }
        }
    }

    /// Persists source, rendered preview, and glyph operations for gallery / resume.
    func saveArtworkToLibrary(library: ArtworkLibrary) async {
        await persistArtworkToLibrary(library: library, userInitiated: true)
    }

    /// Writes the current canvas to disk; updates `activeArtworkID`. Silent failures when `userInitiated` is false (e.g. playback auto-archive).
    /// When `pauseOptimizationFirst` is false, the optimization loop is left running (e.g. save at `start()` before the detached task runs).
    func persistArtworkToLibrary(
        library: ArtworkLibrary,
        userInitiated: Bool,
        bumpCreatedAt: Bool = false,
        successMessage: String? = nil,
        pauseOptimizationFirst: Bool = true
    ) async {
        if pauseOptimizationFirst {
            await pauseAndAwaitTask()
        }
        performPersistArtworkToLibrary(
            library: library,
            userInitiated: userInitiated,
            bumpCreatedAt: bumpCreatedAt,
            successMessage: successMessage
        )
    }

    /// Main-actor snapshot write used by `persistArtworkToLibrary` and `start()` (without pausing the optimizer).
    private func performPersistArtworkToLibrary(
        library: ArtworkLibrary,
        userInitiated: Bool,
        bumpCreatedAt: Bool,
        successMessage: String?
    ) {
        guard let source = sourceImageForOverlay else {
            if userInitiated { exportMessage = "No source image to save." }
            return
        }
        let preview: CGImage?
        if let eng = engine, playbackIndex == glyphHistory.count, !isPlayingBack {
            preview = try? eng.snapshot()
        } else {
            preview = displayImage
        }
        guard let preview else {
            if userInitiated { exportMessage = "Nothing to save." }
            return
        }
        let ops = glyphHistory
        let messageOnSuccess = successMessage ?? "Saved to gallery."
        do {
            let id = try library.saveArtwork(
                source: source,
                preview: preview,
                operations: ops,
                existingArtworkID: activeArtworkID,
                bumpCreatedAt: bumpCreatedAt,
                titlePrefix: pendingImportTitlePrefix
            )
            activeArtworkID = id
            if userInitiated {
                exportMessage = messageOnSuccess
            }
        } catch {
            if userInitiated {
                exportMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    /// Archives the current canvas when starting a new image from the gallery, then clears the studio session.
    func beginNewImageSession(library: ArtworkLibrary) async {
        await pauseAndAwaitTask()
        if sourceImageForOverlay != nil {
            await persistArtworkToLibrary(
                library: library,
                userInitiated: true,
                bumpCreatedAt: true,
                successMessage: "Previous artwork saved to gallery."
            )
        }
        sourceImageForOverlay = nil
        engine = nil
        displayImage = nil
        iterationCount = 0
        glyphCount = 0
        glyphHistory = []
        playbackIndex = 0
        isPlayingBack = false
        isStopped = false
        playbackTask?.cancel()
        playbackTask = nil
        scoreEMA = nil
        referenceError = nil
        progressEstimate = 0
        measuredIterationsPerSecond = 0
        clearOptimizationDebug()
        activeArtworkID = nil
        encodingAutostartSuppressed = false
        pendingImportTitlePrefix = nil
    }

    /// Rebuilds engine and history from a saved gallery document.
    func restoreArtwork(id: UUID, library: ArtworkLibrary) async {
        await pauseAndAwaitTask()
        do {
            let manifest = try library.loadManifest(id: id)
            let source = try library.loadSourceImage(id: id)
            guard source.width == manifest.canvasWidth, source.height == manifest.canvasHeight else {
                exportMessage = "Canvas size mismatch for this artwork."
                return
            }
            let canvasBG =
                (try? ImageProcessing.darkestAmongTopFiveCommonColors(from: source))
                ?? RGBAColor(r: 255, g: 255, b: 255, a: 255)
            try await historyStore.importOperations(
                manifest.operations,
                width: manifest.canvasWidth,
                height: manifest.canvasHeight,
                canvasBackground: canvasBG
            )
            let engine = try GlyphRenderEngine(
                target: source,
                canvasBackground: canvasBG,
                initialEncodingComparisonMode: encodingComparisonMode
            )
            engine.rebuildCanvas(from: manifest.operations, encodingComparisonMode: encodingComparisonMode)
            let snapshot = try engine.snapshot()
            sourceImageForOverlay = source
            self.engine = engine
            glyphHistory = manifest.operations
            glyphCount = manifest.operations.count
            playbackIndex = manifest.operations.count
            displayImage = snapshot
            iterationCount = 0
            isRunning = false
            isPlayingBack = false
            isStopped = false
            playbackTask?.cancel()
            playbackTask = nil
            scoreEMA = nil
            referenceError = nil
            progressEstimate = 0
            measuredIterationsPerSecond = 0
            clearOptimizationDebug()
            exportMessage = nil
            activeArtworkID = manifest.id
            pendingImportTitlePrefix = manifest.titlePrefix
            applyStudioPresetFromSettings()
        } catch {
            exportMessage = "Could not open artwork: \(error.localizedDescription)"
            sourceImageForOverlay = nil
            self.engine = nil
            displayImage = nil
            glyphHistory = []
            glyphCount = 0
            playbackIndex = 0
            activeArtworkID = nil
            pendingImportTitlePrefix = nil
        }
    }

    @MainActor
    func clearOptimizationDebug() {
        debugLastStepLoss = nil
        debugLastFitness = nil
        debugLastGeneration = nil
        debugLastEvaluations = nil
        debugLastRegion = nil
    }

    /// Keeps per-cell region weights in sync when switching encoding mode; resets progress smoothing (different loss scale).
    func syncEncodingComparisonModeToEngine() {
        engine?.setEncodingComparisonMode(encodingComparisonMode)
        referenceError = nil
        scoreEMA = nil
    }

    /// Updates `displayImage` from the engine snapshot (live) or history replay (scrub/playback).
    func refreshTimelineDisplay() async {
        guard let engine else {
            displayImage = nil
            return
        }
        let count = glyphHistory.count
        let idx = max(0, min(playbackIndex, count))
        playbackIndex = idx
        if idx == count, !isPlayingBack {
            displayImage = try? engine.snapshot()
        } else {
            displayImage = try? await historyStore.render(upTo: idx)
        }
    }

    func setTimelinePlaybackIndex(_ index: Int) {
        let capped = max(0, min(index, glyphHistory.count))
        playbackIndex = capped
        isPlayingBack = false
        playbackLoops = false
        playbackTask?.cancel()
        playbackTask = nil
        Task { await refreshTimelineDisplay() }
    }

    func stopTimeline() {
        isStopped = true
        isPlayingBack = false
        playbackLoops = false
        playbackTask?.cancel()
        playbackTask = nil
    }

    /// Stops gallery fullscreen loop playback without toggling encoding `isStopped` (standalone playback VM).
    func endGalleryLoopPlaybackSession() {
        isPlayingBack = false
        playbackLoops = false
        playbackTask?.cancel()
        playbackTask = nil
    }

    func togglePlayback(library: ArtworkLibrary) {
        if isPlayingBack {
            isPlayingBack = false
            playbackLoops = false
            playbackTask?.cancel()
            playbackTask = nil
            return
        }
        guard !glyphHistory.isEmpty else { return }
        Task {
            await persistArtworkToLibrary(library: library, userInitiated: false)
            await MainActor.run {
                self.playbackLoops = false
                if self.playbackIndex >= self.glyphHistory.count {
                    self.playbackIndex = 0
                }
                self.isPlayingBack = true
                self.playbackTask = Task { await self.runPlaybackLoop() }
            }
        }
    }

    /// Looping playback for gallery fullscreen (does not toggle off studio timeline behavior elsewhere).
    func startLoopingPlayback(library: ArtworkLibrary) {
        guard !glyphHistory.isEmpty else { return }
        playbackLoops = true
        isPlayingBack = false
        playbackTask?.cancel()
        playbackTask = nil
        Task {
            await persistArtworkToLibrary(library: library, userInitiated: false)
            await MainActor.run {
                if self.playbackIndex >= self.glyphHistory.count {
                    self.playbackIndex = 0
                }
                self.isPlayingBack = true
                self.playbackTask = Task { await self.runPlaybackLoop() }
            }
        }
    }

    private func runPlaybackLoop() async {
        while !Task.isCancelled {
            let stepNanos = await MainActor.run {
                UInt64((1_000_000_000.0 / max(1.0, self.playbackGlyphsPerSecond)).rounded())
            }
            try? await Task.sleep(nanoseconds: max(1, stepNanos))
            let done = await MainActor.run { () -> Bool in
                guard self.isPlayingBack else { return true }
                if self.playbackIndex >= self.glyphHistory.count {
                    self.isPlayingBack = false
                    return true
                }
                self.playbackIndex += 1
                if self.playbackIndex >= self.glyphHistory.count {
                    if self.playbackLoops {
                        self.playbackIndex = 0
                    } else {
                        self.isPlayingBack = false
                    }
                }
                return false
            }
            await refreshTimelineDisplay()
            if done { break }
        }
        await MainActor.run {
            self.playbackTask = nil
            Task { await self.refreshTimelineDisplay() }
        }
    }

    /// Pauses looping gallery playback without clearing the loop intent (used by gallery fullscreen).
    func pauseGalleryLoopPlayback() {
        isPlayingBack = false
        playbackTask?.cancel()
        playbackTask = nil
    }

    /// Resumes gallery looping playback after `pauseGalleryLoopPlayback`.
    func resumeGalleryLoopPlayback(library: ArtworkLibrary) {
        guard playbackLoops, !glyphHistory.isEmpty else { return }
        Task {
            await persistArtworkToLibrary(library: library, userInitiated: false)
            await MainActor.run {
                if self.playbackIndex >= self.glyphHistory.count {
                    self.playbackIndex = 0
                }
                self.isPlayingBack = true
                self.playbackTask = Task { await self.runPlaybackLoop() }
            }
        }
    }

    /// Truncates history at the current `playbackIndex` and rebuilds the optimizer canvas (timeline fork).
    func continueGenerationFromCurrentFrame() async {
        await pause()
        let k = playbackIndex
        let engineSnapshot = await MainActor.run { self.engine }
        guard let eng = engineSnapshot else { return }
        do {
            try await historyStore.truncate(keepingFirst: k)
            let prefix = await historyStore.copyOperations()
            await MainActor.run {
                self.glyphHistory = prefix
                self.glyphCount = prefix.count
                self.playbackIndex = prefix.count
                self.isStopped = false
                self.isPlayingBack = false
                eng.rebuildCanvas(from: prefix, encodingComparisonMode: self.encodingComparisonMode)
                self.displayImage = try? eng.snapshot()
            }
        } catch {
            await MainActor.run {
                self.exportMessage = "Could not update timeline."
            }
        }
    }

    func exportPNG(library: ArtworkLibrary? = nil) {
        Task {
            await exportPNGAsync(library: library)
        }
    }

    @MainActor
    fileprivate func finishOptimizationLoop() {
        isRunning = false
        optimizationTask = nil
    }

    private func exportPNGAsync(library: ArtworkLibrary?) async {
        guard let cgImage = displayImage, let data = PNGExport.data(from: cgImage) else {
            await MainActor.run { exportMessage = "Could not encode PNG." }
            return
        }
        #if os(iOS)
        await exportToPhotos(data: data, library: library)
        #elseif os(macOS)
        await exportWithSavePanel(data: data, library: library)
        #endif
    }

    #if os(iOS)
    private func exportToPhotos(data: Data, library: ArtworkLibrary?) async {
        let result = await PNGExportPlatform.save(data: data, suggestedFilename: "GlyphCanvas.png")
        switch result {
        case .success(let message):
            await MainActor.run { exportMessage = message }
            await maybeAutoArchiveAfterExport(library: library, photosSucceeded: true)
        case .failure(let error):
            await MainActor.run {
                exportMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }
    #endif

    #if os(macOS)
    private func exportWithSavePanel(data: Data, library: ArtworkLibrary?) async {
        let result = await PNGExportPlatform.save(data: data, suggestedFilename: "GlyphCanvas.png")
        switch result {
        case .success(let message):
            await MainActor.run { exportMessage = message }
            await maybeAutoArchiveAfterExport(library: library, photosSucceeded: true)
        case .failure(let error):
            await MainActor.run {
                if error is PNGExportUserCancelled {
                    exportMessage = nil
                } else {
                    exportMessage = "Save failed: \(error.localizedDescription)"
                }
            }
        }
    }
    #endif

    private func maybeAutoArchiveAfterExport(library: ArtworkLibrary?, photosSucceeded: Bool) async {
        guard photosSucceeded, GlyphCanvasStorageKey.autoArchiveEnabled(), let library else { return }
        await saveArtworkToLibrary(library: library)
        await MainActor.run {
            if self.exportMessage == "Saved to gallery." {
                #if os(iOS)
                self.exportMessage = "Saved to Photos and archived to gallery."
                #else
                self.exportMessage = "Saved and archived to gallery."
                #endif
            }
        }
    }
}

private extension AppViewModel {
    func pauseAndAwaitTask() async {
        let task = optimizationTask
        optimizationTask = nil
        task?.cancel()
        await MainActor.run { self.isRunning = false }
        if let task {
            await task.value
        }
    }

}

/// Runs entirely off the main thread; hops to `MainActor` only for reading settings and publishing UI state.
fileprivate func runGlyphOptimizationLoop(weakViewModel: AppViewModel?) async {
    var localIterationCounter = 0
    var rateWindow: [ContinuousClock.Duration] = []
    let clock = ContinuousClock()
    var lastTick = clock.now
    var lastUIRefresh = clock.now

    while !Task.isCancelled {
        guard let activeEngine = await MainActor.run(body: { weakViewModel?.engine }) else {
            await MainActor.run {
                weakViewModel?.finishOptimizationLoop()
            }
            return
        }

        let timelineSuspended = await MainActor.run {
            guard let vm = weakViewModel else { return true }
            return vm.playbackIndex != vm.glyphHistory.count || vm.isPlayingBack
        }
        if timelineSuspended {
            try? await Task.sleep(nanoseconds: 25_000_000)
            continue
        }

        let settings = await MainActor.run {
            guard let vm = weakViewModel else {
                return (
                    mode: OptimizationMode.greedy,
                    encodingComparisonMode: EncodingComparisonMode.perceptual,
                    colorFidelity: 8.0,
                    regionSize: 12,
                    greedyCandidateCount: 6,
                    geneticConfig: GeneticEvolutionConfig.default,
                    averageFontSize: CGFloat(10),
                    iterationsPerSecond: 120.0,
                    stampPool: StampSetPipeline.activeSet(
                        base: GlyphCanvasCharacterSetDefaults.baseString,
                        mode: .both,
                        source: .characters
                    )
                )
            }
            let pop = max(4, min(24, Int(vm.geneticPopulation.rounded())))
            let gens = max(1, min(15, Int(vm.geneticGenerations.rounded())))
            let maxEval = max(pop, min(256, Int(vm.geneticMaxEvaluations.rounded())))
            let gc = GeneticEvolutionConfig(
                populationSize: pop,
                generations: gens,
                eliteFraction: 0.3,
                maxEvaluations: maxEval
            )
            return (
                mode: vm.optimizationMode,
                encodingComparisonMode: vm.encodingComparisonMode,
                colorFidelity: max(1.0, min(8.0, vm.colorFidelity)),
                regionSize: max(2, Int(vm.regionSize.rounded())),
                greedyCandidateCount: max(1, Int(vm.candidateCount.rounded())),
                geneticConfig: gc,
                averageFontSize: CGFloat(vm.averageFontSize),
                iterationsPerSecond: max(1.0, vm.iterationsPerSecond),
                stampPool: vm.activeStamps
            )
        }

        let now = clock.now
        let dt = now - lastTick
        lastTick = now
        rateWindow.append(dt)
        if rateWindow.count > 50 {
            rateWindow.removeFirst()
        }
        let sumNanos = rateWindow.reduce(0) { $0 + $1.components.attoseconds }
        let measuredIPS: Double
        if rateWindow.isEmpty || sumNanos == 0 {
            measuredIPS = 0
        } else {
            let avgSec = Double(sumNanos) / Double(rateWindow.count) / 1e18
            measuredIPS = avgSec > 0 ? 1.0 / avgSec : 0
        }

        let prevPlayback = await MainActor.run { weakViewModel?.playbackIndex ?? 0 }
        let prevCount = await MainActor.run { weakViewModel?.glyphHistory.count ?? 0 }

        let metrics = activeEngine.performIteration(
            mode: settings.mode,
            encodingComparisonMode: settings.encodingComparisonMode,
            colorFidelity: settings.colorFidelity,
            regionSize: settings.regionSize,
            greedyCandidateCount: settings.greedyCandidateCount,
            geneticConfig: settings.geneticConfig,
            averageFontSize: settings.averageFontSize,
            stampPool: settings.stampPool
        )

        if let op = metrics.committedOperation, let vm = weakViewModel {
            do {
                try await vm.appendToHistoryStore(op)
                await MainActor.run {
                    vm.glyphHistory.append(op)
                    vm.glyphCount = vm.glyphHistory.count
                    if prevPlayback == prevCount {
                        vm.playbackIndex = vm.glyphHistory.count
                    }
                }
            } catch {
                // Store append failed; skip mirroring to avoid divergence.
            }
        }

        await MainActor.run {
            guard let vm = weakViewModel else { return }
            if vm.referenceError == nil {
                vm.referenceError = max(metrics.bestScore, 1e-6)
            }
            let alpha = 0.08
            if let e = vm.scoreEMA {
                vm.scoreEMA = e * (1 - alpha) + metrics.bestScore * alpha
            } else {
                vm.scoreEMA = metrics.bestScore
            }
            let ref = vm.referenceError ?? 1
            let ema = vm.scoreEMA ?? metrics.bestScore
            let raw = 1.0 - min(1.0, ema / ref)
            vm.progressEstimate = max(0, min(1, raw))

            vm.measuredIterationsPerSecond = measuredIPS

            let loss = metrics.bestScore
            vm.debugLastStepLoss = loss.isFinite ? loss : nil
            vm.debugLastFitness = metrics.bestFitness.flatMap { $0.isFinite ? $0 : nil }
            vm.debugLastGeneration = metrics.generationsRun
            vm.debugLastEvaluations = metrics.evaluationsUsed
            vm.debugLastRegion = metrics.lastRegion
        }

        localIterationCounter += 1

        let minFrame: Duration = .milliseconds(50)
        let nowRefresh = clock.now
        let shouldRefresh = localIterationCounter >= 10 || (nowRefresh - lastUIRefresh) >= minFrame

        let useLiveSnapshot = await MainActor.run {
            guard let vm = weakViewModel else { return false }
            return vm.playbackIndex == vm.glyphHistory.count && !vm.isPlayingBack && !vm.suppressLiveDisplayUpdates
        }

        if shouldRefresh {
            if useLiveSnapshot {
                if let image = try? activeEngine.snapshot() {
                    lastUIRefresh = nowRefresh
                    await MainActor.run {
                        guard let vm = weakViewModel else { return }
                        vm.displayImage = image
                        vm.iterationCount += localIterationCounter
                    }
                    localIterationCounter = 0
                }
            } else {
                lastUIRefresh = nowRefresh
                await MainActor.run {
                    guard let vm = weakViewModel else { return }
                    vm.iterationCount += localIterationCounter
                }
                localIterationCounter = 0
            }
        }

        let sleepNanos = UInt64((1_000_000_000.0 / settings.iterationsPerSecond).rounded())
        try? await Task.sleep(nanoseconds: sleepNanos)
    }

    if localIterationCounter > 0 {
        let skipSnapshot = await MainActor.run { weakViewModel?.suppressLiveDisplayUpdates ?? true }
        let eng = await MainActor.run { weakViewModel?.engine }
        if skipSnapshot {
            await MainActor.run {
                guard let vm = weakViewModel else { return }
                vm.iterationCount += localIterationCounter
            }
        } else if let eng, let image = try? eng.snapshot() {
            await MainActor.run {
                guard let vm = weakViewModel else { return }
                vm.displayImage = image
                vm.iterationCount += localIterationCounter
            }
        }
    }

    await MainActor.run {
        weakViewModel?.finishOptimizationLoop()
    }
}

// MARK: - Region sampling weights (testable)

/// Combines residual error and stamp-density penalty for weighted grid picks.
internal enum GlyphRegionPickWeighting {
    static func effectiveWeight(
        cellError: Float,
        stampDensity: Float,
        errorWeightPower: Float,
        epsilon: Float,
        lambdaOverlap: Float
    ) -> Float {
        pow(max(cellError, epsilon), errorWeightPower) / (1 + lambdaOverlap * stampDensity)
    }
}

/// First committed stamps visit n×n image partitions for `n = 2...20` (random cell order per n), then weighted picks take over.
internal enum GlyphEarlyCoveragePhase {
    static let minDivisions = 2
    static let maxDivisions = 20

    /// Sum of `n²` for `n` in `minDivisions...maxDivisions` (2869).
    static var coveragePhaseEndExclusive: Int {
        (minDivisions...maxDivisions).reduce(0) { $0 + $1 * $1 }
    }

    /// Committed indices in `0..<stampBoldCoinFlipEndExclusive` get an independent 50/50 bold vs regular weight.
    static let stampBoldCoinFlipEndExclusive = 2800

    /// Maps committed-stamp index to `(n, slot)` where `n` is the partition count and `slot` is `0..<n²`, or `nil` after the coverage phase.
    static func coverageDivisionAndSlot(sequenceIndex: Int) -> (Int, Int)? {
        guard sequenceIndex >= 0 else { return nil }
        var offset = 0
        for n in minDivisions...maxDivisions {
            let count = n * n
            if sequenceIndex < offset + count {
                return (n, sequenceIndex - offset)
            }
            offset += count
        }
        return nil
    }

    static func randomPointInImagePartition(width: Int, height: Int, divisions n: Int, cellIndex: Int) -> (Int, Int) {
        let col = cellIndex % n
        let row = cellIndex / n
        let x0 = col * width / n
        let x1 = (col + 1) * width / n
        let y0 = row * height / n
        let y1 = (row + 1) * height / n
        let px: Int
        if x1 > x0 {
            px = Int.random(in: x0..<x1)
        } else {
            px = width > 0 ? min(width - 1, max(0, x0)) : 0
        }
        let py: Int
        if y1 > y0 {
            py = Int.random(in: y0..<y1)
        } else {
            py = height > 0 ? min(height - 1, max(0, y0)) : 0
        }
        return (px, py)
    }

    /// Largest scale vs project average at the 2×2 coverage grid; ramps linearly in `n` to 1.0 at 20×20.
    static let maxCoverageFontMultiplier: CGFloat = 2.75

    /// During coverage, reference font scales from `projectAverage * maxCoverageFontMultiplier` at n = 2 down to `projectAverage` at n = 20; afterward returns `projectAverage`.
    static func referenceFontSize(projectAverage: CGFloat, sequenceIndex: Int) -> CGFloat {
        guard let (n, _) = coverageDivisionAndSlot(sequenceIndex: sequenceIndex) else {
            return projectAverage
        }
        let span = CGFloat(maxDivisions - minDivisions)
        let t = span > 0 ? CGFloat(n - minDivisions) / span : 0
        let multiplier = maxCoverageFontMultiplier * (1 - t) + 1.0 * t
        return projectAverage * multiplier
    }
}

// MARK: - Last glyph params per grid cell (temporal smoothing)

private struct LastCellGlyph: Sendable {
    var stamp: String
    var fontSize: CGFloat
    var rotationDegrees: Int
}

// MARK: - Glyph render engine

/// 1) Early committed stamps: random point in each cell of n×n partitions for n = 2…20 (shuffled visit order per n), with reference font size ramping from large (2×2) to project average (20×20); then weighted-random region (error grid + occasional uniform exploration).
/// 2) Representative color + coverage-aware character, with optional reuse from the same grid cell.
/// 3) Quantized font size / rotation; optional temporal blend from last commit in-cell.
/// 4) Score = perceptual region error + smoothness penalty vs last commit; cached glyph bitmap is composited into a **region-sized scratch** buffer (full canvas only for commits).
struct IterationMetrics: Sendable {
    let committed: Bool
    /// Primary metric for progress (total loss, lower better); matches historical greedy behavior.
    let bestScore: Double
    let bestFitness: Double?
    let generationsRun: Int
    let evaluationsUsed: Int
    let lastRegion: PixelRegion?
    /// Recorded when `committed` is true; used for timeline history.
    let committedOperation: GlyphOperation?
}

final class GlyphRenderEngine: @unchecked Sendable {
    private let targetBuffer: PixelBuffer
    /// Precomputed soft edge strength (red channel 0…255); same size as `targetBuffer`.
    private let edgeStrengthBuffer: PixelBuffer
    private let canvasBuffer: PixelBuffer
    private let canvasContext: CGContext
    private let canvasBackground: RGBAColor
    private let width: Int
    private let height: Int

    private let cellSize = 12
    private let gridWidth: Int
    private let gridHeight: Int
    private var cellError: [Float]
    /// How often each grid cell has been covered by a committed stamp (decays each pick).
    private var cellStampDensity: [Float]
    private var cellLastGlyph: [LastCellGlyph?]
    private var cellBestGenome: [GlyphGenome?]

    private let glyphCache = GlyphBitmapCache()
    private var scratchBuffer: PixelBuffer?
    private var scratchContext: CGContext?

    /// Weighted pick: `error^power`; higher = more focus on bad cells.
    private let errorWeightPower: Float = 1.35
    /// Deprioritizes cells that already received many stamps (spread coverage).
    private let lambdaOverlap: Float = 0.35
    /// Per pick, decay stamp density so refinement can return to dense areas later.
    private let stampDensityDecay: Float = 0.995
    /// Occasionally sample uniformly so no cell starves.
    private let explorationUniformRate: Double = 0.08
    /// Blend toward previous cell glyph params.
    private let blendProbability: Double = 0.35
    /// Penalize large jumps from last committed glyph in this cell.
    private let lambdaRotation: Double = 0.0015
    private let lambdaSize: Double = 0.04

    /// Drives `refreshAllCellErrors` and candidate scoring for this session (updated each iteration and on rebuild).
    private var encodingComparisonMode: EncodingComparisonMode

    private var nextSequenceIndex: Int = 0
    /// For each `n` in `2...20`, a shuffled list of linear cell indices `0..<n²` (slot → partition cell).
    private let coverageCellPermutations: [[Int]]

    init(target: CGImage, canvasBackground: RGBAColor, initialEncodingComparisonMode: EncodingComparisonMode = .perceptual) throws {
        let targetBuffer = try ImageProcessing.makePixelBuffer(from: target)
        let edgeStrengthBuffer = ImageProcessing.makeEdgeStrengthBuffer(from: targetBuffer)
        let canvasBuffer = PixelBuffer(width: target.width, height: target.height)
        guard let context = ImageProcessing.makeContext(width: target.width, height: target.height, data: canvasBuffer.data) else {
            throw ImageProcessingError.contextFailure
        }

        self.targetBuffer = targetBuffer
        self.edgeStrengthBuffer = edgeStrengthBuffer
        self.encodingComparisonMode = initialEncodingComparisonMode
        self.canvasBuffer = canvasBuffer
        self.canvasContext = context
        self.canvasBackground = canvasBackground
        self.width = target.width
        self.height = target.height

        let gw = max(1, (target.width + cellSize - 1) / cellSize)
        let gh = max(1, (target.height + cellSize - 1) / cellSize)
        self.gridWidth = gw
        self.gridHeight = gh
        self.cellError = [Float](repeating: 1, count: gw * gh)
        self.cellStampDensity = [Float](repeating: 0, count: gw * gh)
        self.cellLastGlyph = [LastCellGlyph?](repeating: nil, count: gw * gh)
        self.cellBestGenome = [GlyphGenome?](repeating: nil, count: gw * gh)
        self.coverageCellPermutations = (GlyphEarlyCoveragePhase.minDivisions...GlyphEarlyCoveragePhase.maxDivisions).map { n in
            Array(0..<(n * n)).shuffled()
        }

        context.setFillColor(canvasBackground.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        refreshAllCellErrors()
    }

    /// Call when `EncodingComparisonMode` changes without recreating the engine (refreshes per-cell weights).
    func setEncodingComparisonMode(_ mode: EncodingComparisonMode) {
        encodingComparisonMode = mode
        refreshAllCellErrors()
    }

    private func cellIndex(px: Int, py: Int) -> Int {
        let cx = min(gridWidth - 1, max(0, px / cellSize))
        let cy = min(gridHeight - 1, max(0, py / cellSize))
        return cy * gridWidth + cx
    }

    private func pickRegionCenter() -> (Int, Int) {
        if let (n, slot) = GlyphEarlyCoveragePhase.coverageDivisionAndSlot(sequenceIndex: nextSequenceIndex) {
            let cellIndex = coverageCellPermutations[n - GlyphEarlyCoveragePhase.minDivisions][slot]
            return GlyphEarlyCoveragePhase.randomPointInImagePartition(
                width: width,
                height: height,
                divisions: n,
                cellIndex: cellIndex
            )
        }
        if Double.random(in: 0..<1) < explorationUniformRate {
            return (Int.random(in: 0..<width), Int.random(in: 0..<height))
        }
        let eps: Float = 0.02
        var total: Float = 0
        for i in 0..<cellError.count {
            total += GlyphRegionPickWeighting.effectiveWeight(
                cellError: cellError[i],
                stampDensity: cellStampDensity[i],
                errorWeightPower: errorWeightPower,
                epsilon: eps,
                lambdaOverlap: lambdaOverlap
            )
        }
        var r = Float.random(in: 0..<max(total, 0.02))
        var idx = 0
        for i in 0..<cellError.count {
            let w = GlyphRegionPickWeighting.effectiveWeight(
                cellError: cellError[i],
                stampDensity: cellStampDensity[i],
                errorWeightPower: errorWeightPower,
                epsilon: eps,
                lambdaOverlap: lambdaOverlap
            )
            r -= w
            if r <= 0 {
                idx = i
                break
            }
        }
        let cx = idx % gridWidth
        let cy = idx / gridWidth
        let px = min(width - 1, cx * cellSize + Int.random(in: 0..<cellSize))
        let py = min(height - 1, cy * cellSize + Int.random(in: 0..<cellSize))
        return (px, py)
    }

    private func pixelRegionForCell(cx: Int, cy: Int) -> PixelRegion {
        let x = cx * cellSize
        let y = cy * cellSize
        let w = max(0, min(cellSize, width - x))
        let h = max(0, min(cellSize, height - y))
        return PixelRegion(x: x, y: y, width: w, height: h)
    }

    private func refreshAllCellErrors() {
        for cy in 0..<gridHeight {
            for cx in 0..<gridWidth {
                let i = cy * gridWidth + cx
                let pr = pixelRegionForCell(cx: cx, cy: cy)
                guard pr.width > 0, pr.height > 0 else {
                    cellError[i] = 0
                    continue
                }
                cellError[i] = Float(ImageProcessing.regionEncodingLossAligned(
                    mode: encodingComparisonMode,
                    candidate: canvasBuffer,
                    target: targetBuffer,
                    edgeStrength: edgeStrengthBuffer,
                    region: pr,
                    canvasBackground: canvasBackground
                ))
            }
        }
    }

    /// Updates per-cell residual error from the live canvas and increments stamp density for overlapped cells.
    private func updateCellErrorsAndStampDensity(forCommittedRegion region: PixelRegion) {
        let x0 = max(0, region.x / cellSize)
        let y0 = max(0, region.y / cellSize)
        let x1 = min(gridWidth - 1, (region.x + region.width - 1) / cellSize)
        let y1 = min(gridHeight - 1, (region.y + region.height - 1) / cellSize)
        for cy in y0...y1 {
            for cx in x0...x1 {
                let i = cy * gridWidth + cx
                let pr = pixelRegionForCell(cx: cx, cy: cy)
                guard pr.width > 0, pr.height > 0 else { continue }
                cellError[i] = Float(ImageProcessing.regionEncodingLossAligned(
                    mode: encodingComparisonMode,
                    candidate: canvasBuffer,
                    target: targetBuffer,
                    edgeStrength: edgeStrengthBuffer,
                    region: pr,
                    canvasBackground: canvasBackground
                ))
                cellStampDensity[i] += 1
            }
        }
    }

    private func ensureScratch(width rw: Int, height rh: Int) {
        if scratchBuffer?.width == rw, scratchBuffer?.height == rh, scratchContext != nil {
            return
        }
        scratchBuffer = PixelBuffer(width: rw, height: rh)
        guard let ctx = ImageProcessing.makeContext(width: rw, height: rh, data: scratchBuffer!.data) else {
            scratchContext = nil
            return
        }
        scratchContext = ctx
    }

    /// One optimization step: greedy **or** localized GA for the chosen region, then commit the winner.
    func performIteration(
        mode: OptimizationMode,
        encodingComparisonMode: EncodingComparisonMode,
        colorFidelity: Double,
        regionSize: Int,
        greedyCandidateCount: Int,
        geneticConfig: GeneticEvolutionConfig,
        averageFontSize: CGFloat,
        stampPool: [String]
    ) -> IterationMetrics {
        self.encodingComparisonMode = encodingComparisonMode

        if Task.isCancelled {
            return IterationMetrics(
                committed: false,
                bestScore: .infinity,
                bestFitness: nil,
                generationsRun: 0,
                evaluationsUsed: 0,
                lastRegion: nil,
                committedOperation: nil
            )
        }

        for i in 0..<cellStampDensity.count {
            cellStampDensity[i] *= stampDensityDecay
        }

        let effectiveRef = GlyphEarlyCoveragePhase.referenceFontSize(
            projectAverage: averageFontSize,
            sequenceIndex: nextSequenceIndex
        )
        let stampIsBold =
            nextSequenceIndex < GlyphEarlyCoveragePhase.stampBoldCoinFlipEndExclusive && Bool.random()

        let (centerX, centerY) = pickRegionCenter()
        let region = ImageProcessing.clampedRegion(
            centerX: centerX,
            centerY: centerY,
            regionSize: min(regionSize, min(width, height)),
            width: width,
            height: height
        )

        let meanY = ImageProcessing.meanLuminance(in: region, from: targetBuffer)
        let rgb = ImageProcessing.representativeColor(in: region, from: targetBuffer)
        let colorQuantizationStep = ImageProcessing.colorQuantizationStep(forFidelity: colorFidelity)
        let dominantColor = ImageProcessing.quantizeRGB(ImageProcessing.rgbaColor(from: rgb), step: colorQuantizationStep)

        let baseline = canvasBuffer.copyRegion(region)
        let primaryCell = cellIndex(px: region.x + region.width / 2, py: region.y + region.height / 2)

        ensureScratch(width: region.width, height: region.height)
        guard let scratchBuffer, let scratchContext else {
            return IterationMetrics(
                committed: false,
                bestScore: .infinity,
                bestFitness: nil,
                generationsRun: 0,
                evaluationsUsed: 0,
                lastRegion: region,
                committedOperation: nil
            )
        }

        switch mode {
        case .greedy:
            return greedyStep(
                region: region,
                baseline: baseline,
                scratchBuffer: scratchBuffer,
                scratchContext: scratchContext,
                primaryCell: primaryCell,
                meanY: meanY,
                dominantColor: dominantColor,
                colorQuantizationStep: colorQuantizationStep,
                candidateCount: greedyCandidateCount,
                averageFontSize: effectiveRef,
                stampIsBold: stampIsBold,
                stampPool: stampPool,
                encodingComparisonMode: encodingComparisonMode
            )
        case .genetic:
            return geneticStep(
                region: region,
                baseline: baseline,
                scratchBuffer: scratchBuffer,
                scratchContext: scratchContext,
                primaryCell: primaryCell,
                meanY: meanY,
                baseRGB: ImageProcessing.quantizeRGB(rgb, step: colorQuantizationStep),
                colorQuantizationStep: colorQuantizationStep,
                config: geneticConfig,
                averageFontSize: effectiveRef,
                stampIsBold: stampIsBold,
                stampPool: stampPool,
                encodingComparisonMode: encodingComparisonMode
            )
        }
    }

    private func greedyStep(
        region: PixelRegion,
        baseline: [UInt8],
        scratchBuffer: PixelBuffer,
        scratchContext: CGContext,
        primaryCell: Int,
        meanY: Double,
        dominantColor: RGBAColor,
        colorQuantizationStep: Int,
        candidateCount: Int,
        averageFontSize: CGFloat,
        stampIsBold: Bool,
        stampPool: [String],
        encodingComparisonMode: EncodingComparisonMode
    ) -> IterationMetrics {
        var bestCandidate: GlyphCandidate?
        var bestScore = Double.infinity

        for _ in 0..<candidateCount {
            if Task.isCancelled {
                break
            }
            let stamp: String
            if Double.random(in: 0..<1) < blendProbability, let last = cellLastGlyph[primaryCell] {
                stamp = Double.random(in: 0..<1) < 0.5
                    ? last.stamp
                    : ImageProcessing.randomCoverageAwareStamp(meanLuminanceY: meanY, stampPool: stampPool)
            } else {
                stamp = ImageProcessing.randomCoverageAwareStamp(meanLuminanceY: meanY, stampPool: stampPool)
            }

            var fs = averageFontSize + CGFloat.random(in: -2...2)
            var rot = CGFloat.random(in: (-.pi / 2)...(.pi / 2))

            if Double.random(in: 0..<1) < blendProbability, let last = cellLastGlyph[primaryCell] {
                fs = last.fontSize * 0.55 + fs * 0.45
                let lastRad = CGFloat(last.rotationDegrees) * .pi / 180
                rot = lastRad * 0.55 + rot * 0.45 + CGFloat.random(in: -0.12...0.12)
            }

            fs = max(4, ImageProcessing.quantizedFontSize(fs))
            let qDeg = ImageProcessing.quantizedRotationDegrees(rot)
            let qRad = ImageProcessing.radians(fromQuantizedDegrees: qDeg)

            let candidate = GlyphCandidate(
                character: stamp,
                fontSize: fs,
                rotationRadians: qRad,
                color: ImageProcessing.quantizeRGB(dominantColor, step: colorQuantizationStep),
                region: region,
                isBold: stampIsBold
            )

            let key = GlyphRenderKey(glyph: candidate)
            guard
                let glyphImage = glyphCache.image(for: key, create: {
                    ImageProcessing.renderGlyphBitmap(
                        character: candidate.character,
                        fontSize: key.quantizedFontSize,
                        rotationRadians: ImageProcessing.radians(fromQuantizedDegrees: key.quantizedRotationDegrees),
                        color: ImageProcessing.rgbaColor(
                            from: SIMD3<Float>(
                                Float(key.quantizedR),
                                Float(key.quantizedG),
                                Float(key.quantizedB)
                            )
                        ),
                        isBold: key.isBold
                    )
                })
            else {
                continue
            }

            scratchBuffer.load(from: baseline)
            ImageProcessing.compositeCachedGlyph(
                glyphImage,
                scratchWidth: region.width,
                scratchHeight: region.height,
                offsetX: candidate.centerOffsetX,
                offsetY: candidate.centerOffsetY,
                in: scratchContext
            )

            var score = ImageProcessing.regionEncodingLoss(
                mode: encodingComparisonMode,
                candidate: scratchBuffer,
                target: targetBuffer,
                edgeStrength: edgeStrengthBuffer,
                region: region,
                canvasBackground: canvasBackground
            )

            if let last = cellLastGlyph[primaryCell] {
                let dRot = abs(qRad - CGFloat(last.rotationDegrees) * .pi / 180)
                let dSize = abs(fs - last.fontSize)
                score += lambdaRotation * Double(dRot) + lambdaSize * Double(dSize)
            }

            if score < bestScore {
                bestScore = score
                bestCandidate = candidate
            }
        }

        return commitIfNeeded(
            bestCandidate: bestCandidate,
            bestScore: bestScore,
            region: region,
            primaryCell: primaryCell,
            generationsRun: 1,
            evaluationsUsed: candidateCount,
            bestFitness: nil
        )
    }

    private func geneticStep(
        region: PixelRegion,
        baseline: [UInt8],
        scratchBuffer: PixelBuffer,
        scratchContext: CGContext,
        primaryCell: Int,
        meanY: Double,
        baseRGB: SIMD3<Float>,
        colorQuantizationStep: Int,
        config: GeneticEvolutionConfig,
        averageFontSize: CGFloat,
        stampIsBold: Bool,
        stampPool: [String],
        encodingComparisonMode: EncodingComparisonMode
    ) -> IterationMetrics {
        let prior = cellLastGlyph[primaryCell].map {
            GlyphCellPrior(stamp: $0.stamp, fontSize: $0.fontSize, rotationDegrees: $0.rotationDegrees)
        }
        let seed = cellBestGenome[primaryCell]

        let evolution = GlyphEvolutionEngine.evolve(
            config: config,
            seedFromCache: seed,
            region: region,
            meanLuminanceY: meanY,
            averageFontSize: averageFontSize,
            baseRGB: baseRGB,
            colorQuantizationStep: colorQuantizationStep,
            stampPool: stampPool,
            stampIsBold: stampIsBold,
            evaluateFitness: { genome in
                let candidate = genome.toCandidate(region: region)
                let key = GlyphRenderKey(glyph: candidate)
                guard
                    let glyphImage = glyphCache.image(for: key, create: {
                        ImageProcessing.renderGlyphBitmap(
                            character: candidate.character,
                            fontSize: key.quantizedFontSize,
                            rotationRadians: ImageProcessing.radians(fromQuantizedDegrees: key.quantizedRotationDegrees),
                            color: ImageProcessing.rgbaColor(
                                from: SIMD3<Float>(
                                    Float(key.quantizedR),
                                    Float(key.quantizedG),
                                    Float(key.quantizedB)
                                )
                            ),
                            isBold: key.isBold
                        )
                    })
                else {
                    return nil
                }

                scratchBuffer.load(from: baseline)
                ImageProcessing.compositeCachedGlyph(
                    glyphImage,
                    scratchWidth: region.width,
                    scratchHeight: region.height,
                    offsetX: candidate.centerOffsetX,
                    offsetY: candidate.centerOffsetY,
                    in: scratchContext
                )

                let pe = ImageProcessing.regionEncodingLoss(
                    mode: encodingComparisonMode,
                    candidate: scratchBuffer,
                    target: targetBuffer,
                    edgeStrength: edgeStrengthBuffer,
                    region: region,
                    canvasBackground: canvasBackground
                )
                return GlyphFitness.fitness(
                    perceptualError: pe,
                    genome: genome,
                    lastInCell: prior,
                    referenceAverageFontSize: averageFontSize
                )
            },
            shouldCancel: { Task.isCancelled }
        )

        guard let bestGenome = evolution.bestGenome else {
            let fallback = ImageProcessing.regionEncodingLossAligned(
                mode: encodingComparisonMode,
                candidate: canvasBuffer,
                target: targetBuffer,
                edgeStrength: edgeStrengthBuffer,
                region: region,
                canvasBackground: canvasBackground
            )
            return IterationMetrics(
                committed: false,
                bestScore: fallback,
                bestFitness: evolution.bestFitnessLastGeneration.isFinite ? evolution.bestFitnessLastGeneration : nil,
                generationsRun: evolution.generationsRun,
                evaluationsUsed: evolution.evaluationsUsed,
                lastRegion: region,
                committedOperation: nil
            )
        }

        cellBestGenome[primaryCell] = bestGenome
        let bestCandidate = bestGenome.toCandidate(region: region)

        let key = GlyphRenderKey(glyph: bestCandidate)
        guard
            let glyphImage = glyphCache.image(for: key, create: {
                ImageProcessing.renderGlyphBitmap(
                    character: bestCandidate.character,
                    fontSize: key.quantizedFontSize,
                    rotationRadians: ImageProcessing.radians(fromQuantizedDegrees: key.quantizedRotationDegrees),
                    color: ImageProcessing.rgbaColor(
                        from: SIMD3<Float>(
                            Float(key.quantizedR),
                            Float(key.quantizedG),
                            Float(key.quantizedB)
                        )
                    ),
                    isBold: key.isBold
                )
            })
        else {
            return IterationMetrics(
                committed: false,
                bestScore: evolution.bestLoss,
                bestFitness: nil,
                generationsRun: evolution.generationsRun,
                evaluationsUsed: evolution.evaluationsUsed,
                lastRegion: region,
                committedOperation: nil
            )
        }

        scratchBuffer.load(from: baseline)
        ImageProcessing.compositeCachedGlyph(
            glyphImage,
            scratchWidth: region.width,
            scratchHeight: region.height,
            offsetX: bestCandidate.centerOffsetX,
            offsetY: bestCandidate.centerOffsetY,
            in: scratchContext
        )
        let pe = ImageProcessing.regionEncodingLoss(
            mode: encodingComparisonMode,
            candidate: scratchBuffer,
            target: targetBuffer,
            edgeStrength: edgeStrengthBuffer,
            region: region,
            canvasBackground: canvasBackground
        )
        let totalLoss = GlyphFitness.totalLoss(
            perceptualError: pe,
            genome: bestGenome,
            lastInCell: prior,
            referenceAverageFontSize: averageFontSize
        )
        let bestFit = GlyphFitness.fitness(
            perceptualError: pe,
            genome: bestGenome,
            lastInCell: prior,
            referenceAverageFontSize: averageFontSize
        )

        return commitIfNeeded(
            bestCandidate: bestCandidate,
            bestScore: totalLoss,
            region: region,
            primaryCell: primaryCell,
            generationsRun: evolution.generationsRun,
            evaluationsUsed: evolution.evaluationsUsed,
            bestFitness: bestFit
        )
    }

    private func commitIfNeeded(
        bestCandidate: GlyphCandidate?,
        bestScore: Double,
        region: PixelRegion,
        primaryCell: Int,
        generationsRun: Int,
        evaluationsUsed: Int,
        bestFitness: Double?
    ) -> IterationMetrics {
        var score = bestScore
        let committed: Bool
        var committedOp: GlyphOperation?
        if let best = bestCandidate {
            ImageProcessing.drawGlyph(best, in: canvasContext)
            updateCellErrorsAndStampDensity(forCommittedRegion: region)

            let qd = ImageProcessing.quantizedRotationDegrees(best.rotationRadians)
            let st = best.character.isEmpty ? "?" : best.character
            cellLastGlyph[primaryCell] = LastCellGlyph(stamp: st, fontSize: best.fontSize, rotationDegrees: qd)
            committed = true
            let seq = nextSequenceIndex
            nextSequenceIndex += 1
            committedOp = GlyphOperation(from: best, sequenceIndex: seq)
        } else {
            committed = false
            committedOp = nil
        }

        if score == .infinity || score.isNaN {
            score = ImageProcessing.regionEncodingLossAligned(
                mode: encodingComparisonMode,
                candidate: canvasBuffer,
                target: targetBuffer,
                edgeStrength: edgeStrengthBuffer,
                region: region,
                canvasBackground: canvasBackground
            )
        }

        return IterationMetrics(
            committed: committed,
            bestScore: score,
            bestFitness: bestFitness,
            generationsRun: generationsRun,
            evaluationsUsed: evaluationsUsed,
            lastRegion: region,
            committedOperation: committedOp
        )
    }

    /// Rebuilds canvas and regional optimizer state from a prefix of operations (timeline fork).
    func rebuildCanvas(from operations: [GlyphOperation], encodingComparisonMode: EncodingComparisonMode) {
        self.encodingComparisonMode = encodingComparisonMode
        canvasContext.setFillColor(canvasBackground.cgColor)
        canvasContext.fill(CGRect(x: 0, y: 0, width: width, height: height))

        cellLastGlyph = [LastCellGlyph?](repeating: nil, count: gridWidth * gridHeight)
        cellBestGenome = [GlyphGenome?](repeating: nil, count: gridWidth * gridHeight)
        cellStampDensity = [Float](repeating: 0, count: gridWidth * gridHeight)
        nextSequenceIndex = 0

        refreshAllCellErrors()

        for op in operations {
            let best = op.makeCandidate()
            let region = op.region
            let primaryCell = cellIndex(px: region.x + region.width / 2, py: region.y + region.height / 2)
            ImageProcessing.drawGlyph(best, in: canvasContext)
            updateCellErrorsAndStampDensity(forCommittedRegion: region)
            let qd = ImageProcessing.quantizedRotationDegrees(best.rotationRadians)
            let st = best.character.isEmpty ? "?" : best.character
            cellLastGlyph[primaryCell] = LastCellGlyph(stamp: st, fontSize: best.fontSize, rotationDegrees: qd)
            nextSequenceIndex += 1
        }
    }

    func snapshot() throws -> CGImage {
        guard let image = canvasContext.makeImage() else {
            throw ImageProcessingError.contextFailure
        }
        return image
    }
}

extension AppViewModel {
    fileprivate func appendToHistoryStore(_ op: GlyphOperation) async throws {
        try await historyStore.append(op)
    }
}

