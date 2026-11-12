//
//  CaptionVideoView.swift
//  GlyphCanvas
//
//  Pick a video; its speech becomes glyph captions burned into every frame.
//

import AVKit
import Observation
import PhotosUI
import SwiftUI

@Observable
final class CaptionVideoSession {
    private(set) var source: TransitionSource?
    var lines: [CaptionLine] = [] {
        didSet { if lines != oldValue { scheduleRefresh() } }
    }
    var videoInk = false {
        didSet { if videoInk != oldValue { scheduleRefresh() } }
    }
    private(set) var loading = false
    /// 0...1 while transcribing.
    private(set) var transcribeProgress: Double?
    private(set) var exportProgress: Double?
    var exported: ExportedVideo?
    var errorMessage: String?

    let player = AVPlayer()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var transcribeTask: Task<Void, Never>?

    func load(_ item: PhotosPickerItem) async {
        loading = true
        defer { loading = false }
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else { return }
            let source = try await TransitionSource.load(movie.url)
            self.source = source
            lines = []
            transcribe()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func transcribe() {
        guard let source else { return }
        transcribeTask?.cancel()
        transcribeProgress = 0
        transcribeTask = Task { [weak self] in
            do {
                let lines = try await CaptionTranscriber.transcribe(source) { p in
                    Task { @MainActor in
                        if self?.transcribeProgress != nil { self?.transcribeProgress = p }
                    }
                }
                guard let self, !Task.isCancelled else { return }
                self.transcribeProgress = nil
                self.lines = lines
                if lines.isEmpty { self.errorMessage = "No speech found in that video." }
            } catch {
                guard !Task.isCancelled else { return }
                self?.transcribeProgress = nil
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self, !Task.isCancelled, let source = self.source else { return }
            do {
                let composition = try await CaptionRenderer(lines: self.lines, videoInk: self.videoInk).videoComposition(for: source.asset)
                guard !Task.isCancelled else { return }
                let item = AVPlayerItem(asset: source.asset)
                item.videoComposition = composition
                let resumeAt = self.player.currentTime()
                let wasPlaying = self.player.timeControlStatus == .playing
                self.player.replaceCurrentItem(with: item)
                await self.player.seek(to: resumeAt, toleranceBefore: .zero, toleranceAfter: .zero)
                if wasPlaying { self.player.play() }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func export() async {
        guard let source else { return }
        player.pause()
        exportProgress = 0
        defer { exportProgress = nil }
        do {
            let composition = try await CaptionRenderer(lines: lines, videoInk: videoInk).videoComposition(for: source.asset)
            let url = try await ExportedVideo.export(source.asset, videoComposition: composition, name: "GlyphCaptions") { [weak self] in
                self?.exportProgress = $0
            }
            exported = ExportedVideo(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func seek(to seconds: Double) {
        player.seek(to: TransitionComposer.cm(seconds), toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

struct CaptionVideoView: View {
    @Environment(\.appTheme) private var theme
    @State private var session = CaptionVideoSession()
    @State private var pick: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Group {
                if session.source != nil {
                    editor
                } else {
                    picker
                }
            }
            .navigationTitle("Captions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task { await session.load(item) }
        }
        .sheet(item: $session.exported) { video in
            ExportedVideoSheet(video: video, title: "Your captioned video")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    private var picker: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Pick a video with someone talking. What they say becomes a pile of words along the bottom of the frame, changing line by line, so the captions are part of the video.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                PhotosPicker(selection: $pick, matching: .videos, preferredItemEncoding: .current) {
                    HStack(spacing: 14) {
                        Image(systemName: "captions.bubble.fill")
                            .font(.title)
                            .foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Video").font(.headline)
                            Text("Choose from Photos")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if session.loading { ProgressView() }
                    }
                    .padding(18)
                    .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private var editor: some View {
        VStack(spacing: 10) {
            VideoPlayer(player: session.player)
                .aspectRatio(session.source.map { $0.displaySize.width / max(1, $0.displaySize.height) } ?? 16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
                .overlay(alignment: .topTrailing) {
                    if let p = session.transcribeProgress {
                        Label("Listening \(Int(p * 100))%", systemImage: "waveform")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(24)
                    }
                }
            Toggle("Colour words from the video", isOn: $session.videoInk)
                .padding(.horizontal, 16)
            List($session.lines) { $line in
                HStack(alignment: .firstTextBaseline) {
                    Button(VideoTransitionView.time(line.start)) { session.seek(to: line.start) }
                        .font(.caption.monospacedDigit())
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Jump to this line")
                    TextField("Caption", text: $line.text, axis: .vertical)
                }
            }
            .listStyle(.plain)
            .frame(maxHeight: 260)
            .overlay {
                if session.lines.isEmpty, session.transcribeProgress == nil {
                    Text("No captions yet.").foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if session.source != nil {
            ToolbarItem(placement: .navigation) {
                PhotosPicker(selection: $pick, matching: .videos, preferredItemEncoding: .current) {
                    Label("Replace video", systemImage: "film")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if let p = session.exportProgress {
                    ProgressView(value: p)
                        .frame(width: 80)
                        .accessibilityLabel("Exporting")
                } else {
                    Button("Export", systemImage: "square.and.arrow.up") {
                        Task { await session.export() }
                    }
                    .disabled(session.transcribeProgress != nil || session.lines.isEmpty)
                }
            }
        }
    }
}
