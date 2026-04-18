//
//  ContentView.swift
//  GlyphCanvas
//
//  Created by Nathan Fennel on 4/16/26.
//

import SwiftUI
import UniformTypeIdentifiers

enum StudioContentLayoutMode {
    case main
    case advanced
}

struct ContentView: View {
    @AppStorage(GlyphCanvasStorageKey.baseCharacterSet) private var storedBaseCharacterSet = GlyphCanvasCharacterSetDefaults.baseString
    @AppStorage(GlyphCanvasStorageKey.characterCaseMode) private var storedCharacterCaseMode = CharacterCaseMode.both.rawValue
    @AppStorage(GlyphCanvasStorageKey.highDetailMode) private var storedHighDetailMode = true
    @AppStorage(GlyphCanvasStorageKey.showSourceOverlay) private var storedShowSourceOverlay = false
    @AppStorage(GlyphCanvasStorageKey.optimizationMode) private var storedOptimizationMode = OptimizationMode.greedy.rawValue
    @AppStorage(GlyphCanvasStorageKey.debugOptimizationOverlay) private var storedDebugOptimizationOverlay = false

    @ObservedObject var viewModel: AppViewModel
    @EnvironmentObject private var library: ArtworkLibrary
    var layoutMode: StudioContentLayoutMode = .main
    var autoPresentImagePicker: Binding<Bool>? = nil

    @State private var showStudioCanvasFullscreen = false
    @State private var studioCanvasScrollDisabled = false

    init(
        viewModel: AppViewModel,
        layoutMode: StudioContentLayoutMode = .main,
        autoPresentImagePicker: Binding<Bool>? = nil
    ) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.layoutMode = layoutMode
        self.autoPresentImagePicker = autoPresentImagePicker
    }

    var body: some View {
        Group {
            switch layoutMode {
            case .main:
                mainStudioLayout
            case .advanced:
                advancedControlsLayout
            }
        }
        .font(.system(.body, design: .monospaced))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(GalleryTheme.galleryScreenBackground.ignoresSafeArea())
        .onAppear {
            viewModel.baseCharacterSet = storedBaseCharacterSet
            viewModel.characterCaseMode = CharacterCaseMode(rawValue: storedCharacterCaseMode) ?? .both
            viewModel.showSourceOverlay = storedShowSourceOverlay
            viewModel.optimizationMode = OptimizationMode(rawValue: storedOptimizationMode) ?? .greedy
            viewModel.debugOptimizationOverlay = storedDebugOptimizationOverlay
            viewModel.applyStudioPresetFromSettings()
        }
        .onChange(of: storedBaseCharacterSet) { _, newValue in
            viewModel.baseCharacterSet = newValue
        }
        .onChange(of: storedCharacterCaseMode) { _, newValue in
            viewModel.characterCaseMode = CharacterCaseMode(rawValue: newValue) ?? .both
        }
        .onChange(of: viewModel.baseCharacterSet) { _, newValue in
            if newValue != storedBaseCharacterSet {
                storedBaseCharacterSet = newValue
            }
        }
        .onChange(of: viewModel.characterCaseMode) { _, newValue in
            if newValue.rawValue != storedCharacterCaseMode {
                storedCharacterCaseMode = newValue.rawValue
            }
        }
        .onChange(of: storedHighDetailMode) { _, _ in
            viewModel.applyStudioPresetFromSettings()
        }
        .onChange(of: storedShowSourceOverlay) { _, newValue in
            viewModel.showSourceOverlay = newValue
        }
        .onChange(of: storedOptimizationMode) { _, newValue in
            viewModel.optimizationMode = OptimizationMode(rawValue: newValue) ?? .greedy
        }
        .onChange(of: storedDebugOptimizationOverlay) { _, newValue in
            viewModel.debugOptimizationOverlay = newValue
        }
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
        .onChange(of: viewModel.debugOptimizationOverlay) { _, newValue in
            if newValue != storedDebugOptimizationOverlay {
                storedDebugOptimizationOverlay = newValue
            }
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

    private var mainStudioLayout: some View {
        Group {
            if viewModel.hasLoadedImage {
                ScrollView {
                    VStack(spacing: 14) {
                        sourcePanel
                        encodingPanel
                        statusStrip
                        parameterPanel
                    }
                }
                .scrollDisabled(studioCanvasScrollDisabled)
            } else {
                emptyStudioSelectImageLayout
            }
        }
    }

    private var emptyStudioSelectImageLayout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            PlatformImagePicker(
                onImagePicked: { viewModel.loadImage($0) },
                autoPresentImagePicker: autoPresentImagePicker
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [UTType.image.identifier], isTargeted: nil) { providers in
            handleDrop(providers)
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
                        PlatformImagePicker { cgImage in
                            viewModel.loadImage(cgImage)
                        }
                    }
                }
                .padding(12)
            } else {
                PlatformImagePicker(onImagePicked: { viewModel.loadImage($0) })
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
            VStack(alignment: .leading, spacing: 10) {
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

                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("ENCODING_SEQUENCE")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(GalleryTheme.bodyMuted)
                            Spacer()
                            Text("\(Int((viewModel.progressEstimate * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(GalleryTheme.hudDetail)
                        }
                        ProgressView(value: viewModel.progressEstimate)
                            .tint(GalleryTheme.studioAccent)
                    }
                }
            }
        }
    }

    private var advancedControlsLayout: some View {
        ScrollView {
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
                    let maxIndex = max(0, viewModel.glyphHistory.count)
                    let visibleLabel = min(viewModel.playbackIndex, maxIndex)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Timeline")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Glyph \(visibleLabel) / \(maxIndex)")
                            .font(.caption.monospacedDigit())
                        Slider(
                            value: Binding(
                                get: { Double(viewModel.playbackIndex) },
                                set: { viewModel.setTimelinePlaybackIndex(Int($0.rounded())) }
                            ),
                            in: 0...Double(max(0, maxIndex)),
                            step: 1
                        )
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

                VStack(alignment: .leading, spacing: 6) {
                    TextField("Character Set", text: $storedBaseCharacterSet, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .font(.body)
                    if viewModel.showsCharacterSetFallbackNotice {
                        Text("Character set empty; using defaults.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Picker("Case filter", selection: caseModeBinding) {
                        ForEach(CharacterCaseMode.allCases, id: \.self) { mode in
                            Image(systemName: mode.sfSymbolName)
                                .tag(mode)
                                .accessibilityLabel(mode.accessibilityLabel)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Picker("Optimization mode", selection: $viewModel.optimizationMode) {
                    Text("Greedy").tag(OptimizationMode.greedy)
                    Text("Evolutionary").tag(OptimizationMode.genetic)
                }
                .pickerStyle(.segmented)

                Toggle("Show optimization debug", isOn: $viewModel.debugOptimizationOverlay)
                    .disabled(!viewModel.hasLoadedImage)

                if viewModel.debugOptimizationOverlay, viewModel.hasLoadedImage {
                    OptimizationDebugPanel(viewModel: viewModel)
                }

                SliderRow(
                    title: "Target iter/s",
                    value: $viewModel.iterationsPerSecond,
                    range: 1...300,
                    step: 1,
                    format: "%.0f"
                )
                SliderRow(
                    title: "Region size",
                    value: $viewModel.regionSize,
                    range: 4...24,
                    step: 1,
                    format: "%.0f"
                )
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

                SliderRow(
                    title: "Avg font size",
                    value: $viewModel.averageFontSize,
                    range: 6...24,
                    step: 0.5,
                    format: "%.1f"
                )
            }
        }
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
                viewModel.loadImage(image)
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
    ContentView(viewModel: AppViewModel())
        .environmentObject(ArtworkLibrary())
}
