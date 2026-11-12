//
//  VideoTransitionView.swift
//  GlyphCanvas
//
//  Pick two clips; clip 2's first frame is rebuilt in glyphs over clip 1, then clip 2 plays.
//

import AVKit
import PhotosUI
import SwiftUI

struct VideoTransitionView: View {
    @Environment(\.appTheme) private var theme
    @AppStorage(GlyphRevealStyle.storageKey) private var storedStyle = GlyphRevealStyle.pop.rawValue

    @State private var session = VideoTransitionSession()
    @State private var pick1: PhotosPickerItem?
    @State private var pick2: PhotosPickerItem?

    private var style: GlyphRevealStyle { GlyphRevealStyle(rawValue: storedStyle) ?? .pop }

    var body: some View {
        NavigationStack {
            Group {
                if session.edit != nil {
                    editor
                } else {
                    picker
                }
            }
            .navigationTitle("Transitions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
        }
        .onChange(of: pick1) { _, item in
            guard let item else { return }
            Task { await session.load(item, slot: 1) }
        }
        .onChange(of: pick2) { _, item in
            guard let item else { return }
            Task { await session.load(item, slot: 2) }
        }
        .onChange(of: storedStyle) { _, _ in session.rebuildPreview() }
        .sheet(item: $session.exported) { video in
            ExportedVideoSheet(video: video)
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

    // MARK: Empty state

    private var picker: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Pick a background clip and an incoming clip. The incoming clip's first frame builds itself out of glyphs on top of the background, then starts playing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                clipCard(slot: 1, title: "Background clip", systemImage: "1.circle.fill", loaded: session.clip1 != nil, selection: $pick1)
                clipCard(slot: 2, title: "Incoming clip", systemImage: "2.circle.fill", loaded: session.clip2 != nil, selection: $pick2)
            }
            .padding(20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private func clipCard(slot: Int, title: LocalizedStringKey, systemImage: String, loaded: Bool, selection: Binding<PhotosPickerItem?>) -> some View {
        PhotosPicker(selection: selection, matching: .videos, preferredItemEncoding: .current) {
            HStack(spacing: 14) {
                Image(systemName: loaded ? "checkmark.circle.fill" : systemImage)
                    .font(.title)
                    .foregroundStyle(loaded ? .green : theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(loaded ? "Ready, tap to replace" : "Choose from Photos")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if session.loadingClip == slot { ProgressView() }
            }
            .padding(18)
            .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Editor

    private var editor: some View {
        VStack(spacing: 10) {
            preview
            transport
            if let editBinding {
                TransitionTimelineView(
                    edit: editBinding,
                    currentTime: session.currentTime,
                    media1: session.media1,
                    media2: session.media2,
                    styleIcon: style.systemImage,
                    onScrub: { session.scrub(to: $0) },
                    onScrubbingChanged: { session.isScrubbing = $0 }
                )
                ScrollView {
                    TransitionInspector(edit: editBinding, planProgress: session.planProgress)
                        .padding(.horizontal, 16)
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(.vertical, 8)
    }

    private var editBinding: Binding<TransitionEdit>? {
        guard session.edit != nil else { return nil }
        return Binding(
            get: { session.edit ?? TransitionEdit(clip1Duration: 1, clip2Duration: 1) },
            set: { session.edit = $0 }
        )
    }

    private var preview: some View {
        VideoPlayer(player: session.player)
            .aspectRatio(session.clip1.map { $0.displaySize.width / max(1, $0.displaySize.height) } ?? 16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .overlay(alignment: .topTrailing) {
                if let p = session.planProgress {
                    Label("Building glyphs \(Int(p * 100))%", systemImage: "character.textbox")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(24)
                }
            }
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Button {
                session.togglePlay()
            } label: {
                Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(session.isPlaying ? "Pause" : "Play")

            Text("\(Self.time(session.currentTime)) / \(Self.time(session.edit?.outputDuration ?? 0))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            GlyphRevealStyleMenu()
        }
        .padding(.horizontal, 16)
    }

    static func time(_ t: Double) -> String {
        let tenths = Int((t * 10).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if session.edit != nil {
            ToolbarItem(placement: .navigation) {
                Menu {
                    PhotosPicker("Replace background clip", selection: $pick1, matching: .videos, preferredItemEncoding: .current)
                    PhotosPicker("Replace incoming clip", selection: $pick2, matching: .videos, preferredItemEncoding: .current)
                } label: {
                    Label("Clips", systemImage: "film")
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
                    .disabled(session.planProgress != nil)
                }
            }
        }
    }
}

// MARK: - Inspector

private struct TransitionInspector: View {
    @Binding var edit: TransitionEdit
    let planProgress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Glyph coverage", value: "\(Int(edit.coverage * 100))%") {
                Slider(value: $edit.coverage, in: 0.3...1)
            }
            volumeRow("Background volume", volume: $edit.clip1Volume)
            volumeRow("Incoming volume", volume: $edit.clip2Volume)
            row("Audio crossfade", value: String(format: "%.1fs", edit.audioFade)) {
                Slider(value: $edit.audioFade, in: 0...3, step: 0.1)
            }
            if edit.clip1AudioTail < edit.audioFade - 0.05 {
                Text("The background clip ends \(edit.clip1AudioTail, specifier: "%.1f")s after the cut, so its audio fades out early. Trim it to start earlier, or move the cut back, for a longer crossfade.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Drag the white handles to trim. Long-press the incoming clip and drag to move the cut. Pinch the timeline to zoom.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row<Control: View>(_ title: LocalizedStringKey, value: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            control()
        }
    }

    private func volumeRow(_ title: LocalizedStringKey, volume: Binding<Float>) -> some View {
        row(title, value: "\(Int(volume.wrappedValue * 100))%") {
            HStack {
                Button {
                    volume.wrappedValue = volume.wrappedValue > 0 ? 0 : 1
                } label: {
                    Image(systemName: volume.wrappedValue > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .frame(width: 22)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(volume.wrappedValue > 0 ? "Mute" : "Unmute")
                Slider(value: volume, in: 0...2)
            }
        }
    }
}

// MARK: - Export result

struct ExportedVideoSheet: View {
    let video: ExportedVideo
    var title: LocalizedStringKey = "Your transition"
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                ShareLink(item: video.url, preview: SharePreview(title)) {
                    Label("Share video", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                let p = AVPlayer(url: video.url)
                player = p
                p.play()
            }
            .onDisappear { player?.pause() }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 520)
        #endif
    }
}
