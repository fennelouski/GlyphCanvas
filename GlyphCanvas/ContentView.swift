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

    @ObservedObject var viewModel: AppViewModel
    @EnvironmentObject private var library: ArtworkLibrary
    var autoPresentImagePicker: Binding<Bool>? = nil
    var jumpToReviewSection: Binding<Bool> = .constant(false)

    @State private var showStudioCanvasFullscreen = false
    @State private var studioCanvasScrollDisabled = false
    @State private var importAdjustItem: ImportAdjustItem?
    @State private var reviewExportAdvancedExpanded = false

    init(
        viewModel: AppViewModel,
        autoPresentImagePicker: Binding<Bool>? = nil,
        jumpToReviewSection: Binding<Bool> = .constant(false)
    ) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.autoPresentImagePicker = autoPresentImagePicker
        self.jumpToReviewSection = jumpToReviewSection
    }

    var body: some View {
        studioRootWithSheets
    }

    private var studioFramedLayout: some View {
        mainStudioLayout
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, studioContentHorizontalPadding)
            .padding(.vertical, 12)
            .background(GalleryTheme.galleryScreenBackground.ignoresSafeArea())
            .onAppear {
                applyStorageToViewModelOnAppear()
            }
    }

    /// Split long `onChange` chains so the Swift compiler can type-check `ContentView`.
    private var studioFramedWithCharacterObservers: some View {
        studioFramedLayout
            .onChange(of: storedBaseCharacterSet) { _, newValue in
                viewModel.baseCharacterSet = newValue
            }
            .onChange(of: storedStampSourceMode) { _, newValue in
                viewModel.stampSourceMode = StampSourceMode(rawValue: newValue) ?? .characters
            }
            .onChange(of: storedCharacterCaseMode) { _, newValue in
                viewModel.characterCaseMode = CharacterCaseMode(rawValue: newValue) ?? .both
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
        viewModel.showSourceOverlay = storedShowSourceOverlay
        viewModel.optimizationMode = OptimizationMode(rawValue: storedOptimizationMode) ?? .greedy
        viewModel.encodingComparisonMode = EncodingComparisonMode(rawValue: storedEncodingComparisonMode) ?? .perceptual
        viewModel.debugOptimizationOverlay = storedDebugOptimizationOverlay
        viewModel.colorFidelity = max(1.0, min(8.0, storedColorFidelity))
        viewModel.applyStudioPresetFromSettings()
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

    /// Edge-to-edge canvas width on iPhone / compact; controls below stay inset.
    private var studioCanvasShouldExpandToFullWidth: Bool {
        guard viewModel.hasLoadedImage else { return false }
        #if os(iOS)
        return true
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var characterSetSummaryLine: String {
        let modeTag = viewModel.stampSourceMode == .words ? "words" : "chars"
        let trimmed = storedBaseCharacterSet.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "\(modeTag) · (defaults) · \(viewModel.activeStamps.count) stamps" }
        let maxLen = 36
        let snippet: String
        if trimmed.count <= maxLen { snippet = trimmed }
        else { snippet = String(trimmed.prefix(maxLen)) + "…" }
        return "\(modeTag) · \(snippet) · \(viewModel.activeStamps.count) stamps"
    }

    private var studioContentHorizontalPadding: CGFloat {
        studioCanvasShouldExpandToFullWidth ? 0 : 14
    }

    private var mainStudioLayout: some View {
        Group {
            if viewModel.hasLoadedImage {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            if studioCanvasShouldExpandToFullWidth {
                                studioSetupPanel
                                    .padding(.horizontal, 14)
                                sourcePanel
                                studioControlsColumn
                                    .padding(.horizontal, 14)
                            } else {
                                studioSetupPanel
                                sourcePanel
                                studioControlsColumn
                            }
                        }
                    }
                    .scrollDisabled(studioCanvasScrollDisabled)
                    .onChange(of: jumpToReviewSection.wrappedValue) { _, shouldJump in
                        guard shouldJump else { return }
                        reviewExportAdvancedExpanded = true
                        withAnimation {
                            proxy.scrollTo("studioReviewSection", anchor: .top)
                        }
                        jumpToReviewSection.wrappedValue = false
                    }
                }
            } else {
                emptyStudioSelectImageLayout
            }
        }
    }

    /// Encode transport, status, PARAMETERS, and secondary review/export/advanced — single column below the canvas when edge-to-edge.
    private var studioControlsColumn: some View {
        VStack(spacing: 14) {
            encodingPanel
            statusStrip
            parameterPanel
            studioReviewExportAdvancedCard
        }
    }

    private var emptyStudioSelectImageLayout: some View {
        ScrollView {
            VStack(spacing: 14) {
                studioSetupPanel
                Group {
#if os(macOS)
                    WideStudioEmptyImportView(
                        onImagePicked: { cg, hints in stageImageForStudio(cg, hints: hints) },
                        autoPresentImagePicker: autoPresentImagePicker
                    )
#elseif os(iOS)
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        WideStudioEmptyImportView(
                            onImagePicked: { cg, hints in stageImageForStudio(cg, hints: hints) },
                            autoPresentImagePicker: autoPresentImagePicker
                        )
                    } else if UIDevice.current.userInterfaceIdiom == .phone {
                        StudioEmptyStateView(
                            onImagePicked: { cg, hints in stageImageForStudio(cg, hints: hints) },
                            autoPresentImagePicker: autoPresentImagePicker
                        )
                    } else {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            PlatformImagePicker(
                                onImagePicked: { cg, hints in stageImageForStudio(cg, hints: hints) },
                                autoPresentImagePicker: autoPresentImagePicker
                            )
                            Spacer(minLength: 0)
                        }
                    }
#else
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        PlatformImagePicker(
                            onImagePicked: { cg, hints in stageImageForStudio(cg, hints: hints) },
                            autoPresentImagePicker: autoPresentImagePicker
                        )
                        Spacer(minLength: 0)
                    }
#endif
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [UTType.image.identifier], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private var studioSetupPanel: some View {
        StudioSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Rectangle()
                        .fill(GalleryTheme.studioAccent)
                        .frame(width: 4, height: 16)
                    Text("SETUP")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(GalleryTheme.headline)
                    Spacer()
                    Text("CT_SPEC_01")
                        .font(.caption2.monospaced())
                        .foregroundStyle(GalleryTheme.hudDetail)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Set: \(characterSetSummaryLine)")
                        .font(.caption.monospaced())
                        .foregroundStyle(GalleryTheme.bodyMuted)
                        .lineLimit(3)
                    if viewModel.showsCharacterSetFallbackNotice {
                        Text("No stamps from this input; using defaults.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink(value: StudioRoute.characterSetEditor) {
                        HStack {
                            Text("Edit stamps")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(GalleryTheme.hudDetail)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(GalleryTheme.headline)
                }

                Picker("Case filter", selection: caseModeBinding) {
                    ForEach(CharacterCaseMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.sfSymbolName)
                            .tag(mode)
                            .accessibilityLabel(mode.accessibilityLabel)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Optimization mode", selection: $viewModel.optimizationMode) {
                    Text("Greedy").tag(OptimizationMode.greedy)
                    Text("Evolutionary").tag(OptimizationMode.genetic)
                }
                .pickerStyle(.segmented)

                Text("Encoding")
                    .font(.caption2.monospaced())
                    .foregroundStyle(GalleryTheme.bodyMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Picker("Encoding comparison", selection: $viewModel.encodingComparisonMode) {
                    Text(EncodingComparisonMode.perceptual.displayLabel).tag(EncodingComparisonMode.perceptual)
                    Text(EncodingComparisonMode.edges.displayLabel).tag(EncodingComparisonMode.edges)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Encoding comparison")
            }
        }
    }

    private var sourcePanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.4))
            if let image = viewModel.displayImage {
                StudioMosaicInteractiveCanvas(
                    displayImage: image,
                    sourceOverlay: viewModel.sourceImageForOverlay,
                    showSourceOverlay: viewModel.showSourceOverlay,
                    imagePadding: 10,
                    onRequestFullscreen: {
                        showStudioCanvasFullscreen = true
                    },
                    scrollDisabledBinding: $studioCanvasScrollDisabled
                )
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        PlatformImagePicker { cgImage, hints in
                            stageImageForStudio(cgImage, hints: hints)
                        }
                    }
                }
                .padding(12)
            } else {
                PlatformImagePicker(onImagePicked: { cg, hints in stageImageForStudio(cg, hints: hints) })
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(
            DashedRoundedRectangle()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .foregroundStyle(GalleryTheme.studioStroke)
        )
        .onDrop(of: [UTType.image.identifier], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showStudioCanvasFullscreen) {
            Group {
                if let image = viewModel.displayImage {
                    StudioMosaicFullscreenShell(
                        displayImage: image,
                        sourceOverlay: viewModel.sourceImageForOverlay,
                        showSourceOverlay: viewModel.showSourceOverlay,
                        isPresented: $showStudioCanvasFullscreen
                    )
                } else {
                    Color.clear
                        .onAppear { showStudioCanvasFullscreen = false }
                }
            }
        }
        #else
        .sheet(isPresented: $showStudioCanvasFullscreen) {
            if let image = viewModel.displayImage {
                StudioMosaicFullscreenShell(
                    displayImage: image,
                    sourceOverlay: viewModel.sourceImageForOverlay,
                    showSourceOverlay: viewModel.showSourceOverlay,
                    isPresented: $showStudioCanvasFullscreen
                )
            }
        }
        #endif
    }

    private var statusStrip: some View {
        HStack(spacing: 8) {
            Text("BUFFER: \(bufferEstimateLabel)")
                .foregroundStyle(GalleryTheme.hudDetail)
            Spacer()
            Text("●")
                .foregroundStyle(viewModel.isRunning ? GalleryTheme.studioAccent : GalleryTheme.studioStatusRed)
            Text(viewModel.isRunning ? "ENCODING" : "STBY_MODE")
                .foregroundStyle(viewModel.isRunning ? GalleryTheme.studioAccent : GalleryTheme.studioStatusRed)
            Spacer()
            Text("V.\(GalleryTheme.marketingVersion)_IND")
                .foregroundStyle(GalleryTheme.hudDetail)
        }
        .font(.caption2.monospaced())
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(GalleryTheme.cardSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var parameterPanel: some View {
        StudioSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Rectangle()
                        .fill(GalleryTheme.studioAccent)
                        .frame(width: 4, height: 16)
                    Text("PARAMETERS")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(GalleryTheme.headline)
                    Spacer()
                    Text("CT_SPEC_09")
                        .font(.caption2.monospaced())
                        .foregroundStyle(GalleryTheme.hudDetail)
                }

                StudioParameterSlider(
                    title: "DENSITY",
                    value: $viewModel.regionSize,
                    range: 4...24,
                    step: 1,
                    leftLabel: "FINE",
                    rightLabel: "COARSE"
                )
                StudioParameterSlider(
                    title: "IMPACT",
                    value: $viewModel.iterationsPerSecond,
                    range: 1...300,
                    step: 1,
                    leftLabel: "LIGHT",
                    rightLabel: "HEAVY"
                )
                StudioParameterSlider(
                    title: "INK_SPREAD",
                    value: $viewModel.averageFontSize,
                    range: 6...24,
                    step: 0.5,
                    leftLabel: "DRY",
                    rightLabel: "SATURATED"
                )
                SliderRow(
                    title: "Color fidelity",
                    value: colorFidelityBinding,
                    range: 1...8,
                    step: 1,
                    format: "%.0f"
                )

                HStack(spacing: 12) {
                    Button {
                        viewModel.reset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.hasLoadedImage)

                    Button {
                        viewModel.applyStudioPresetFromSettings()
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var encodingPanel: some View {
        StudioSectionCard {
            HStack(spacing: 10) {
                Button {
                    if viewModel.isRunning {
                        Task { await viewModel.pause() }
                    } else {
                        viewModel.start()
                    }
                } label: {
                    Image(systemName: viewModel.isRunning ? "pause.fill" : "play.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.black.opacity(0.8))
                        .frame(width: 52, height: 44)
                        .background(GalleryTheme.studioAccent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.hasLoadedImage || viewModel.playbackIndex != viewModel.glyphHistory.count)

                Button {
                    if viewModel.isPlayingBack {
                        viewModel.stopTimeline()
                    } else if viewModel.isRunning {
                        Task { await viewModel.pauseEncodingAndSuppressAutostart() }
                    }
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isPlayingBack && !viewModel.isRunning)
            }
        }
    }

    private var studioReviewExportAdvancedCard: some View {
        StudioSectionCard {
            DisclosureGroup(isExpanded: $reviewExportAdvancedExpanded) {
                reviewExportAdvancedContent
                    .padding(.top, 8)
            } label: {
                HStack {
                    Rectangle()
                        .fill(GalleryTheme.studioAccent)
                        .frame(width: 4, height: 16)
                    Text("REVIEW, EXPORT & ADVANCED")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(GalleryTheme.headline)
                    Spacer()
                    Text("CT_SPEC_10")
                        .font(.caption2.monospaced())
                        .foregroundStyle(GalleryTheme.hudDetail)
                }
            }
            .tint(GalleryTheme.studioAccent)
        }
        .id("studioReviewSection")
    }

    @ViewBuilder
    private var reviewExportAdvancedContent: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Button("Export PNG") {
                    viewModel.exportPNG(library: library)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.displayImage == nil)

                Button("Save to gallery") {
                    Task {
                        await viewModel.saveArtworkToLibrary(library: library)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.hasLoadedImage)
                Spacer()
            }

            Group {
                let cap = max(0, viewModel.glyphHistory.count)
                let scrubBinding = Binding<Double>(
                    get: {
                        let c = max(0, viewModel.glyphHistory.count)
                        return Double(min(max(0, viewModel.playbackIndex), c))
                    },
                    set: { viewModel.setTimelinePlaybackIndex(Int($0.rounded())) }
                )
                VStack(alignment: .leading, spacing: 8) {
                    Text("Timeline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Glyph \(min(max(0, viewModel.playbackIndex), cap)) / \(cap)")
                        .font(.caption.monospacedDigit())
                    Group {
                        if cap > 0 {
                            Slider(
                                value: scrubBinding,
                                in: 0...Double(cap),
                                step: 1
                            )
                        } else {
                            // `step: 1` with `0...0` trips SwiftUI's Slider preconditions.
                            Slider(value: scrubBinding, in: 0...0)
                        }
                    }
                    .disabled(!viewModel.hasLoadedImage)
                    HStack(spacing: 8) {
                        Button(viewModel.isPlayingBack ? "Pause" : "Play") {
                            viewModel.togglePlayback(library: library)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.hasLoadedImage || viewModel.glyphHistory.isEmpty)

                        Button("Stop") {
                            viewModel.stopTimeline()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.hasLoadedImage || viewModel.glyphHistory.isEmpty)

                        Button("Continue from here") {
                            Task { await viewModel.continueGenerationFromCurrentFrame() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.hasLoadedImage || viewModel.glyphHistory.isEmpty)
                        Spacer()
                    }
                    SliderRow(
                        title: "Playback glyphs/s",
                        value: $viewModel.playbackGlyphsPerSecond,
                        range: 1...120,
                        step: 1,
                        format: "%.0f"
                    )
                    .disabled(!viewModel.hasLoadedImage || viewModel.glyphHistory.isEmpty)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text("Iterations: \(viewModel.iterationCount)")
                Spacer()
                Text("Glyphs: \(viewModel.glyphCount)")
            }
            .font(.caption.monospacedDigit())

            HStack {
                Text("Speed: \(viewModel.measuredIterationsPerSecond, format: .number.precision(.fractionLength(1))) /s")
                Spacer()
                Text("Target: \(viewModel.iterationsPerSecond, format: .number.precision(.fractionLength(0))) /s")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            if let msg = viewModel.exportMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Show source overlay", isOn: $viewModel.showSourceOverlay)
                .disabled(!viewModel.hasLoadedImage)

            Toggle("Show optimization debug", isOn: $viewModel.debugOptimizationOverlay)
                .disabled(!viewModel.hasLoadedImage)

            if viewModel.debugOptimizationOverlay, viewModel.hasLoadedImage {
                OptimizationDebugPanel(viewModel: viewModel)
            }

            SliderRow(
                title: "Candidates (greedy)",
                value: $viewModel.candidateCount,
                range: 2...12,
                step: 1,
                format: "%.0f"
            )

            if viewModel.optimizationMode == .genetic {
                SliderRow(
                    title: "GA population",
                    value: $viewModel.geneticPopulation,
                    range: 12...24,
                    step: 1,
                    format: "%.0f"
                )
                SliderRow(
                    title: "GA generations",
                    value: $viewModel.geneticGenerations,
                    range: 5...15,
                    step: 1,
                    format: "%.0f"
                )
                SliderRow(
                    title: "Max evals / region",
                    value: $viewModel.geneticMaxEvaluations,
                    range: 32...256,
                    step: 8,
                    format: "%.0f"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bufferEstimateLabel: String {
        guard let src = viewModel.sourceImageForOverlay else { return "0.0KB" }
        let bytes = Double(src.width * src.height * 4)
        let kb = bytes / 1024.0
        return String(format: "%.1fKB", kb)
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

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 120, alignment: .leading)
            Slider(value: $value, in: range, step: step)
            Text(String(format: format, value))
                .frame(width: 48, alignment: .trailing)
                .font(.caption.monospacedDigit())
        }
    }
}

#Preview {
    ContentView(viewModel: AppViewModel(), jumpToReviewSection: .constant(false))
        .environmentObject(ArtworkLibrary())
}
