//
//  VideoTransitionSession.swift
//  GlyphCanvas
//

import AVFoundation
import CoreTransferable
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A movie picked from Photos, copied into tmp so it outlives the picker.
nonisolated struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory.appending(path: "clip-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Self(url: dest)
        }
    }
}

struct ExportedVideo: Identifiable {
    let url: URL
    var id: URL { url }
}

@Observable
final class VideoTransitionSession {
    private(set) var clip1: TransitionSource?
    private(set) var clip2: TransitionSource?
    private(set) var media1: ClipMedia?
    private(set) var media2: ClipMedia?

    var edit: TransitionEdit? {
        didSet {
            guard edit != oldValue else { return }
            let planInputsChanged = edit?.clip2In != oldValue?.clip2In || edit?.coverage != oldValue?.coverage
            scheduleRefresh(replan: planInputsChanged)
        }
    }

    private(set) var plan: GlyphPlan = .empty
    /// 0...1 while the glyph plan is being computed.
    private(set) var planProgress: Double?
    private(set) var exportProgress: Double?
    var exported: ExportedVideo?
    var errorMessage: String?
    var loadingClip: Int?

    let player = AVPlayer()
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false

    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var planTask: Task<Void, Never>?
    @ObservationIgnored private var timeObserver: Any?
    /// Set while the user drags the timeline so the time observer doesn't fight the scroll.
    @ObservationIgnored var isScrubbing = false

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlaying = self.player.timeControlStatus == .playing
                if !self.isScrubbing { self.currentTime = time.seconds }
            }
        }
    }

    var style: GlyphRevealStyle {
        GlyphRevealStyle(rawValue: UserDefaults.standard.string(forKey: GlyphRevealStyle.storageKey) ?? "") ?? .pop
    }

    // MARK: Clips

    func load(_ item: PhotosPickerItem, slot: Int) async {
        loadingClip = slot
        defer { loadingClip = nil }
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else { return }
            let source = try await TransitionSource.load(movie.url)
            if slot == 1 {
                clip1 = source
                media1 = nil
            } else {
                clip2 = source
                media2 = nil
            }
            if let c1 = clip1, let c2 = clip2 {
                var fresh = TransitionEdit(clip1Duration: c1.duration, clip2Duration: c2.duration)
                if let old = edit {
                    fresh.clip1Volume = old.clip1Volume
                    fresh.clip2Volume = old.clip2Volume
                    fresh.audioFade = old.audioFade
                    fresh.coverage = old.coverage
                }
                plan = .empty
                edit = fresh
                scheduleRefresh(replan: true)
            }
            let media = await ClipMedia.load(source)
            if slot == 1 { media1 = media } else { media2 = media }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Preview

    func scheduleRefresh(replan: Bool) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled else { return }
            self.rebuildPreview()
            if replan { self.startPlanning() }
        }
    }

    func rebuildPreview() {
        guard let clip1, let clip2, let edit else { return }
        do {
            let built = try TransitionComposer.build(edit: edit, clip1: clip1, clip2: clip2, style: style, plan: plan)
            let item = AVPlayerItem(asset: built.composition)
            item.videoComposition = built.videoComposition
            item.audioMix = built.audioMix
            let resumeAt = min(currentTime, edit.outputDuration)
            let wasPlaying = isPlaying
            player.replaceCurrentItem(with: item)
            seek(to: resumeAt)
            if wasPlaying { player.play() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startPlanning() {
        planTask?.cancel()
        guard let clip1, let clip2, let edit else { return }
        planProgress = 0
        planTask = Task { [weak self] in
            do {
                let frame = try await TransitionComposer.planningFrame(of: clip2, at: edit.clip2In, renderSize: clip1.renderSize)
                let plan = try await TransitionComposer.makePlan(frame: frame, coverage: edit.coverage) { p in
                    self?.planProgress = p
                }
                guard let self, !Task.isCancelled else { return }
                self.plan = plan
                self.planProgress = nil
                self.rebuildPreview()
            } catch is CancellationError {
            } catch {
                self?.planProgress = nil
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func togglePlay() {
        guard let edit else { return }
        if isPlaying {
            player.pause()
        } else {
            if currentTime >= edit.outputDuration - 0.05 { seek(to: 0) }
            player.play()
        }
        isPlaying.toggle()
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        player.seek(to: TransitionComposer.cm(seconds), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func scrub(to seconds: Double) {
        if isPlaying { player.pause(); isPlaying = false }
        seek(to: min(seconds, edit?.outputDuration ?? 0))
    }

    // MARK: Export

    func export() async {
        guard let clip1, let clip2, let edit else { return }
        player.pause()
        exportProgress = 0
        defer { exportProgress = nil }
        // Wait for a pending plan so the export matches what the user tuned.
        while planProgress != nil, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        do {
            let built = try TransitionComposer.build(edit: edit, clip1: clip1, clip2: clip2, style: style, plan: plan)
            guard let session = AVAssetExportSession(asset: built.composition, presetName: AVAssetExportPresetHighestQuality) else {
                throw NSError(domain: "GlyphTransition", code: 4, userInfo: [NSLocalizedDescriptionKey: "Export isn't available on this device."])
            }
            session.videoComposition = built.videoComposition
            session.audioMix = built.audioMix
            let url = FileManager.default.temporaryDirectory.appending(path: "GlyphTransition-\(UUID().uuidString.prefix(8)).mp4")
            let progressTask = Task { [weak self] in
                for await state in session.states(updateInterval: 0.1) {
                    if case .exporting(let progress) = state {
                        self?.exportProgress = progress.fractionCompleted
                    }
                }
            }
            defer { progressTask.cancel() }
            try await session.export(to: url, as: .mp4)
            exported = ExportedVideo(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

