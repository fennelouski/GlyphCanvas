//
//  ContentView.swift
//  GlyphCanvas
//
//  Created by Nathan Fennel on 4/16/26.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

private struct ImportAdjustItem: Identifiable {
    let id = UUID()
    let image: CGImage
    let hints: ImportHints?
}

struct ContentView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage(GlyphCanvasStorageKey.baseCharacterSet) private var storedBaseCharacterSet = GlyphCanvasCharacterSetDefaults.baseString
    @AppStorage(GlyphCanvasStorageKey.stampSourceMode) private var storedStampSourceMode = StampSourceMode.characters.rawValue
    @AppStorage(GlyphCanvasStorageKey.characterCaseMode) private var storedCharacterCaseMode = CharacterCaseMode.both.rawValue
    @AppStorage(GlyphCanvasStorageKey.highDetailMode) private var storedHighDetailMode = true
    @AppStorage(GlyphCanvasStorageKey.showSourceOverlay) private var storedShowSourceOverlay = false
    @AppStorage(GlyphCanvasStorageKey.optimizationMode) private var storedOptimizationMode = OptimizationMode.greedy.rawValue
    @AppStorage(GlyphCanvasStorageKey.encodingComparisonMode) private var storedEncodingComparisonMode = EncodingComparisonMode.perceptual.rawValue
    @AppStorage(GlyphCanvasStorageKey.debugOptimizationOverlay) private var storedDebugOptimizationOverlay = false
    @AppStorage(GlyphCanvasStorageKey.colorFidelity) private var storedColorFidelity = 8.0
    @AppStorage(GlyphCanvasStorageKey.recentStampSets) private var storedRecentStampSets = "[]"

    @ObservedObject var viewModel: AppViewModel
    @EnvironmentObject private var library: ArtworkLibrary
    var autoPresentImagePicker: Binding<Bool>? = nil

    @State private var showStudioCanvasFullscreen = false
    @State private var importAdjustItem: ImportAdjustItem?
    @State private var advancedExpanded = false

    var body: some View {
        studioRootWithSheets
    }

    private var studioFramedLayout: some View {
        mainStudioLayout
            .background(theme.screenBackground.ignoresSafeArea())
            .onAppear {
                applyStorageToViewModelOnAppear()
                #if DEBUG
                // Screenshot / UI-test hook: `-debugLoadImagePath /abs/path.jpg` loads an image without the picker.
                if !viewModel.hasLoadedImage,
                   let path = UserDefaults.standard.string(forKey: "debugLoadImagePath"),
                   let data = FileManager.default.contents(atPath: path),
                   let cg = ImageProcessing.decodeCGImage(data: data) {
                    viewModel.loadImage(cg, hints: ImportHints(imageData: data))
                }
                #endif
            }
    }

    /// Split long `onChange` chains so the Swift compiler can type-check `ContentView`.
    private var studioFramedWithCharacterObservers: some View {
        studioFramedLayout
            .onChange(of: storedBaseCharacterSet) { _, newValue in
                viewModel.baseCharacterSet = newValue
                recordAndPersistRecentStampSet()
            }
            .onChange(of: storedStampSourceMode) { _, newValue in
                viewModel.stampSourceMode = StampSourceMode(rawValue: newValue) ?? .characters
                recordAndPersistRecentStampSet()
            }
            .onChange(of: storedCharacterCaseMode) { _, newValue in
                viewModel.characterCaseMode = CharacterCaseMode(rawValue: newValue) ?? .both
                recordAndPersistRecentStampSet()
            }
            .onChange(of: viewModel.baseCharacterSet) { _, newValue in
                if newValue != storedBaseCharacterSet {
                    storedBaseCharacterSet = newValue
                }
            }
            .onChange(of: viewModel.stampSourceMode) { _, newValue in
                if newValue.rawValue != storedStampSourceMode {
                    storedStampSourceMode = newValue.rawValue
                }
            }
            .onChange(of: viewModel.characterCaseMode) { _, newValue in
                if newValue.rawValue != storedCharacterCaseMode {
                    storedCharacterCaseMode = newValue.rawValue
                }
                recordAndPersistRecentStampSet()
            }
            .onChange(of: viewModel.recentStampSets) { _, _ in
                persistRecentStampSetsFromViewModel()
            }
    }

    private var studioWithPresetObservers: some View {
        studioFramedWithCharacterObservers
            .onChange(of: storedHighDetailMode) { _, _ in
                viewModel.applyStudioPresetFromSettings()
            }
            .onChange(of: storedShowSourceOverlay) { _, newValue in
                viewModel.showSourceOverlay = newValue
            }
            .onChange(of: storedOptimizationMode) { _, newValue in
                viewModel.optimizationMode = OptimizationMode(rawValue: newValue) ?? .greedy
            }
            .onChange(of: storedEncodingComparisonMode) { _, newValue in
                viewModel.encodingComparisonMode = EncodingComparisonMode(rawValue: newValue) ?? .perceptual
                viewModel.syncEncodingComparisonModeToEngine()
            }
            .onChange(of: storedDebugOptimizationOverlay) { _, newValue in
                viewModel.debugOptimizationOverlay = newValue
            }
    }

    private var studioWithViewModelObservers: some View {
        studioWithPresetObservers
            .onChange(of: viewModel.showSourceOverlay) { _, newValue in
                if newValue != storedShowSourceOverlay {
                    storedShowSourceOverlay = newValue
                }
            }
            .onChange(of: viewModel.optimizationMode) { _, newValue in
                if newValue.rawValue != storedOptimizationMode {
                    storedOptimizationMode = newValue.rawValue
                }
            }
            .onChange(of: viewModel.encodingComparisonMode) { _, newValue in
                if newValue.rawValue != storedEncodingComparisonMode {
                    storedEncodingComparisonMode = newValue.rawValue
                }
                viewModel.syncEncodingComparisonModeToEngine()
            }
            .onChange(of: viewModel.debugOptimizationOverlay) { _, newValue in
                if newValue != storedDebugOptimizationOverlay {
                    storedDebugOptimizationOverlay = newValue
                }
            }
    }

    private var studioRootWithObservers: some View {
        studioWithViewModelObservers
            .onChange(of: autoPresentImagePicker?.wrappedValue ?? false) { _, shouldPresent in
                guard shouldPresent, let binding = autoPresentImagePicker else { return }
                guard viewModel.hasLoadedImage else { return }
                Task { @MainActor in
                    await viewModel.beginNewImageSession(library: library)
                    binding.wrappedValue = false
                    await Task.yield()
                    binding.wrappedValue = true
                }
            }
    }

    @ViewBuilder
    private var studioRootWithSheets: some View {
        #if os(macOS)
        studioRootWithObservers
            .sheet(item: $importAdjustItem) { item in
                ImportImageAdjustView(
                    image: item.image,
                    onCancel: { importAdjustItem = nil },
                    onComplete: { cg in
                        viewModel.loadImage(cg, hints: item.hints)
                        importAdjustItem = nil
                    }
                )
                .frame(minWidth: 560, minHeight: 520)
            }
        #else
        studioRootWithObservers
            .fullScreenCover(item: $importAdjustItem) { item in
                ImportImageAdjustView(
                    image: item.image,
                    onCancel: { importAdjustItem = nil },
                    onComplete: { cg in
                        viewModel.loadImage(cg, hints: item.hints)
                        importAdjustItem = nil
                    }
                )
            }
        #endif
    }

    private func stageImageForStudio(_ cg: CGImage, hints: ImportHints?) {
        importAdjustItem = ImportAdjustItem(image: cg, hints: hints)
    }

    private func applyStorageToViewModelOnAppear() {
        viewModel.baseCharacterSet = storedBaseCharacterSet
        viewModel.stampSourceMode = StampSourceMode(rawValue: storedStampSourceMode) ?? .characters
        viewModel.characterCaseMode = CharacterCaseMode(rawValue: storedCharacterCaseMode) ?? .both
        viewModel.loadRecentStampSets(from: storedRecentStampSets)
        viewModel.recordCurrentStampSetInRecents()
        persistRecentStampSetsFromViewModel()
        viewModel.showSourceOverlay = storedShowSourceOverlay
        viewModel.optimizationMode = OptimizationMode(rawValue: storedOptimizationMode) ?? .greedy
        viewModel.encodingComparisonMode = EncodingComparisonMode(rawValue: storedEncodingComparisonMode) ?? .perceptual
        viewModel.debugOptimizationOverlay = storedDebugOptimizationOverlay
        viewModel.colorFidelity = max(1.0, min(8.0, storedColorFidelity))
        viewModel.applyStudioPresetFromSettings()
    }

    private func recordAndPersistRecentStampSet() {
        viewModel.recordCurrentStampSetInRecents()
        persistRecentStampSetsFromViewModel()
    }

    private func persistRecentStampSetsFromViewModel() {
        let encoded = viewModel.encodedRecentStampSetsJSON()
        if storedRecentStampSets != encoded {
            storedRecentStampSets = encoded
        }
    }

    private var caseModeBinding: Binding<CharacterCaseMode> {
        Binding(
            get: { CharacterCaseMode(rawValue: storedCharacterCaseMode) ?? .both },
            set: { newValue in
                storedCharacterCaseMode = newValue.rawValue
                viewModel.characterCaseMode = newValue
            }
        )
    }

    private var colorFidelityBinding: Binding<Double> {
        Binding(
            get: { max(1.0, min(8.0, viewModel.colorFidelity)) },
            set: { newValue in
                let clamped = max(1.0, min(8.0, newValue))
                viewModel.colorFidelity = clamped
                storedColorFidelity = clamped
            }
        )
    }

    private var characterSetSummaryLine: String {
        let stamps = viewModel.activeStamps
        let preview = stamps.prefix(12).joined(separator: " ")
        return stamps.count > 12 ? preview + " …" : preview
    }

    // MARK: - Layout

    /// Side-by-side when there's room (iPad, Mac, unfolded iPhone Duo, landscape); otherwise preview pinned above controls.
    private static func usesSideBySide(_ size: CGSize) -> Bool {
        size.width >= 700 || size.width > size.height * 1.15
    }

    private var mainStudioLayout: some View {
        GeometryReader { geo in
            if !viewModel.hasLoadedImage {
                emptyStudioLayout
            } else if Self.usesSideBySide(geo.size) {
                HStack(spacing: 0) {
                    canvasArea
                        .padding(16)
                    Divider()
                    ScrollView {
                        inspector.padding(16)
                    }
                    .frame(width: min(400, max(320, geo.size.width * 0.34)))
                }
            } else {
                VStack(spacing: 0) {
                    canvasArea
                        .frame(height: min(geo.size.width, geo.size.height * 0.5))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    Divider()
                    ScrollView {
                        inspector.padding(.horizontal, 16).padding(.vertical, 12)
                    }
                }
            }
        }
        .onDrop(of: [UTType.image.identifier], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private var emptyStudioLayout: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 14) {
                    Image(systemName: "character.textbox")
                        .font(.system(size: 52, weight: .regular))
                        .foregroundStyle(theme.accent)
                        .accessibilityHidden(true)
                    Text("Start with a photo")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(GalleryTheme.headline)
                    Text("GlyphCanvas redraws it one character at a time. Change any setting and the artwork redraws immediately.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(GalleryTheme.bodyMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    PlatformImagePicker(
                        onImagePicked: { cg, hints in stageImageForStudio(cg, hints: hints) },
                        autoPresentImagePicker: autoPresentImagePicker
                    )
                    .controlSize(.large)
                    #if os(macOS)
                    Text("or drop an image here")
                        .font(.footnote)
                        .foregroundStyle(GalleryTheme.hudDetail)
                    #endif
                }
                .padding(.vertical, 32)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                glyphsSection
            }
            .frame(maxWidth: 560)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.canvasBackdrop)
                if let image = viewModel.displayImage {
                    StudioMosaicInteractiveCanvas(
                        displayImage: image,
                        sourceOverlay: viewModel.sourceImageForOverlay,
                        showSourceOverlay: viewModel.showSourceOverlay,
                        imagePadding: 10,
                        recentGlyphs: viewModel.recentVisibleGlyphs,
                        onRequestFullscreen: { showStudioCanvasFullscreen = true }
                    )
                }
                statusPill.padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Artwork preview")
            transportBar
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showStudioCanvasFullscreen) { fullscreenCanvas }
        #else
        .sheet(isPresented: $showStudioCanvasFullscreen) { fullscreenCanvas.frame(minWidth: 720, minHeight: 560) }
        #endif
    }

    @ViewBuilder
    private var fullscreenCanvas: some View {
        if let image = viewModel.displayImage {
            StudioMosaicFullscreenShell(
                displayImage: image,
                sourceOverlay: viewModel.sourceImageForOverlay,
                showSourceOverlay: viewModel.showSourceOverlay,
                recentGlyphs: viewModel.recentVisibleGlyphs,
                isPresented: $showStudioCanvasFullscreen
            )
        } else {
            Color.clear.onAppear { showStudioCanvasFullscreen = false }
        }
    }

    private var statusText: LocalizedStringKey {
        if viewModel.isPlayingBack { return "Replaying" }
        if viewModel.isRunning { return "Drawing" }
        if viewModel.playbackIndex < viewModel.glyphHistory.count { return "Scrubbing" }
        return "Paused"
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.isRunning || viewModel.isPlayingBack ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(statusText)
            Text("·")
            Text("\(viewModel.glyphCount) glyphs")
                .monospacedDigit()
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var scrubBinding: Binding<Double> {
        Binding(
            get: { Double(min(max(0, viewModel.playbackIndex), viewModel.glyphHistory.count)) },
            set: { viewModel.setTimelinePlaybackIndex(Int($0.rounded())) }
        )
    }

    /// Play/pause encoding, replay the drawing, and scrub through history — always next to the preview.
    private var transportBar: some View {
        let count = viewModel.glyphHistory.count
        let atLiveEdge = viewModel.playbackIndex == count
        return HStack(spacing: 10) {
            Button {
                if viewModel.isPlayingBack {
                    viewModel.togglePlayback(library: library)
                } else if viewModel.isRunning {
                    Task { await viewModel.pauseEncodingAndSuppressAutostart() }
                } else if atLiveEdge {
                    viewModel.start()
                } else {
                    Task {
                        await viewModel.continueGenerationFromCurrentFrame()
                        viewModel.start()
                    }
                }
            } label: {
                Image(systemName: viewModel.isRunning || viewModel.isPlayingBack ? "pause.fill" : "play.fill")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(viewModel.isRunning || viewModel.isPlayingBack ? "Pause" : (atLiveEdge ? "Draw" : "Continue drawing from here"))

            Button {
                viewModel.restartAnimation(library: library)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.bordered)
            .disabled(count == 0)
            .accessibilityLabel("Replay drawing")

            GlyphRevealStyleMenu()

            Group {
                if count > 0 {
                    Slider(value: scrubBinding, in: 0...Double(count), step: 1)
                } else {
                    // `step: 1` with `0...0` trips SwiftUI's Slider preconditions.
                    Slider(value: .constant(0), in: 0...1).disabled(true)
                }
            }
            .accessibilityLabel("Timeline")
            .accessibilityValue("Glyph \(min(viewModel.playbackIndex, count)) of \(count)")
        }
    }

    // MARK: - Inspector

    private var inspector: some View {
        VStack(spacing: 14) {
            if let msg = viewModel.exportMessage {
                Label(msg, systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(GalleryTheme.bodyMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            lookSection
            glyphsSection
            speedSection
            actionsSection
        }
    }

    private var lookSection: some View {
        StudioSectionCard(title: "Look") {
            Picker("Style", selection: $viewModel.encodingComparisonMode) {
                Text("Match color").tag(EncodingComparisonMode.perceptual)
                Text("Trace edges").tag(EncodingComparisonMode.edges)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Style")

            StudioParameterSlider(
                title: "Detail",
                value: $viewModel.regionSize,
                range: 4...24,
                step: 1,
                leftLabel: "Fine",
                rightLabel: "Bold"
            )
            StudioParameterSlider(
                title: "Glyph size",
                value: $viewModel.averageFontSize,
                range: 6...24,
                step: 0.5,
                leftLabel: "Small",
                rightLabel: "Large",
                format: "%.1f pt"
            )
            StudioParameterSlider(
                title: "Color",
                value: colorFidelityBinding,
                range: 1...8,
                step: 1,
                leftLabel: "Posterized",
                rightLabel: "True color"
            )
            Toggle("Show original underneath", isOn: $viewModel.showSourceOverlay)
                .font(.subheadline)
        }
    }

    private var glyphsSection: some View {
        StudioSectionCard(title: "Glyphs") {
            NavigationLink(value: StudioRoute.characterSetEditor) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(characterSetSummaryLine)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(GalleryTheme.headline)
                            .lineLimit(1)
                        Text(viewModel.stampSourceMode == .words ? "\(viewModel.activeStamps.count) words" : "\(viewModel.activeStamps.count) characters")
                            .font(.caption)
                            .foregroundStyle(GalleryTheme.bodyMuted)
                    }
                    Spacer(minLength: 0)
                    Text("Edit")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.accent)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GalleryTheme.hudDetail)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit glyphs")

            if viewModel.showsCharacterSetFallbackNotice {
                Text("Nothing usable in this input; using the default set.")
                    .font(.caption)
                    .foregroundStyle(GalleryTheme.bodyMuted)
            }

            if viewModel.stampSourceMode == .characters {
                Picker("Letter case", selection: caseModeBinding) {
                    ForEach(CharacterCaseMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.sfSymbolName)
                            .tag(mode)
                            .accessibilityLabel(mode.accessibilityLabel)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Letter case")
            }
        }
    }

    private var speedSection: some View {
        StudioSectionCard(title: "Drawing") {
            StudioParameterSlider(
                title: "Speed",
                value: $viewModel.iterationsPerSecond,
                range: 1...300,
                step: 1,
                leftLabel: "Slow",
                rightLabel: "Fast",
                format: "%.0f/s"
            )
            StudioParameterSlider(
                title: "Replay speed",
                value: $viewModel.playbackGlyphsPerSecond,
                range: 1...120,
                step: 1,
                leftLabel: "Slow",
                rightLabel: "Fast",
                format: "%.0f/s"
            )
            Picker("Method", selection: $viewModel.optimizationMode) {
                Text("Quick").tag(OptimizationMode.greedy)
                Text("Evolutionary").tag(OptimizationMode.genetic)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Method")

            DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
                VStack(spacing: 14) {
                    if viewModel.optimizationMode == .greedy {
                        StudioParameterSlider(
                            title: "Candidates per glyph",
                            value: $viewModel.candidateCount,
                            range: 2...12,
                            step: 1,
                            leftLabel: "Faster",
                            rightLabel: "Better fit"
                        )
                    } else {
                        StudioParameterSlider(
                            title: "Population",
                            value: $viewModel.geneticPopulation,
                            range: 12...24,
                            step: 1,
                            leftLabel: "Faster",
                            rightLabel: "Wider search"
                        )
                        StudioParameterSlider(
                            title: "Generations",
                            value: $viewModel.geneticGenerations,
                            range: 5...15,
                            step: 1,
                            leftLabel: "Faster",
                            rightLabel: "Better fit"
                        )
                        StudioParameterSlider(
                            title: "Max evaluations",
                            value: $viewModel.geneticMaxEvaluations,
                            range: 32...256,
                            step: 8,
                            leftLabel: "Faster",
                            rightLabel: "Better fit"
                        )
                    }
                    Toggle("Show optimization details", isOn: $viewModel.debugOptimizationOverlay)
                        .font(.subheadline)
                    if viewModel.debugOptimizationOverlay {
                        OptimizationDebugPanel(viewModel: viewModel)
                    }
                }
                .padding(.top, 10)
            }
            .font(.subheadline)
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 10) {
            Button {
                Task { await viewModel.saveArtworkToLibrary(library: library) }
            } label: {
                Label("Save to Gallery", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 10) {
                Button {
                    viewModel.exportPNG(library: library)
                } label: {
                    Label("Export PNG", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .disabled(viewModel.displayImage == nil)

                PlatformImagePicker(
                    onImagePicked: { cg, hints in stageImageForStudio(cg, hints: hints) },
                    title: "New Image",
                    prominent: false
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button("Reset settings", systemImage: "arrow.uturn.backward") {
                viewModel.reset()
            }
            .font(.footnote)
            .buttonStyle(.borderless)
            .padding(.top, 4)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else {
            return false
        }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data, let image = ImageProcessing.decodeCGImage(data: data) else { return }
            Task { @MainActor in
                stageImageForStudio(image, hints: ImportHints(imageData: data))
            }
        }
        return true
    }
}

private struct OptimizationDebugPanel: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Debug — \(viewModel.optimizationMode == .greedy ? "Greedy" : "Evolutionary")")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let r = viewModel.debugLastRegion {
                Text("Region \(r.x),\(r.y) · \(r.width)×\(r.height) px")
                    .font(.caption2.monospacedDigit())
            }

            if let loss = viewModel.debugLastStepLoss {
                Text("Loss (lower better) \(loss, format: .number.precision(.fractionLength(4)))")
                    .font(.caption2.monospacedDigit())
            }

            switch viewModel.optimizationMode {
            case .greedy:
                if let n = viewModel.debugLastEvaluations {
                    Text("Scored \(n) candidate\(n == 1 ? "" : "s")")
                        .font(.caption2.monospacedDigit())
                }
            case .genetic:
                if let f = viewModel.debugLastFitness {
                    Text("Fitness (higher better) \(f, format: .number.precision(.fractionLength(4)))")
                        .font(.caption2.monospacedDigit())
                }
                if let g = viewModel.debugLastGeneration, let e = viewModel.debugLastEvaluations {
                    Text("Evolution \(g) gen · \(e) eval")
                        .font(.caption2.monospacedDigit())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    ContentView(viewModel: AppViewModel())
        .environmentObject(ArtworkLibrary())
}
