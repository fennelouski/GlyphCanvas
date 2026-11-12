//
//  EditorView.swift
//  GlyphCanvas
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Owns a fresh `AppViewModel` per session; optionally restores a saved artwork.
struct EditorView: View {
    @Environment(\.appTheme) private var theme
    let resumeArtworkID: UUID?
    var autoPresentImagePicker: Binding<Bool>? = nil

    @StateObject private var viewModel = AppViewModel()
    @EnvironmentObject private var library: ArtworkLibrary
    @Environment(\.scenePhase) private var scenePhase

    #if os(iOS)
    @State private var encodingBackgroundTaskState = EncodingBackgroundTaskState()
    #elseif os(macOS)
    @State private var encodingNapMitigationState = EncodingNapMitigationState()
    #endif

    var body: some View {
        ContentView(viewModel: viewModel, autoPresentImagePicker: autoPresentImagePicker)
            .navigationTitle("Studio")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: StudioRoute.self) { route in
                switch route {
                case .profile:
                    ProfileView()
                case .characterSetEditor:
                    CharacterSetEditorView(viewModel: viewModel)
                }
            }
            .background(theme.screenBackground)
            .task(id: resumeArtworkID) {
                guard let id = resumeArtworkID else { return }
                await viewModel.restoreArtwork(id: id, library: library)
            }
            .onAppear {
                viewModel.galleryLibrary = library
                syncEncodingLifecycle(phase: scenePhase, isRunning: viewModel.isRunning)
            }
            .onChange(of: scenePhase) { _, newPhase in
                syncEncodingLifecycle(phase: newPhase, isRunning: viewModel.isRunning)
            }
            .onChange(of: viewModel.isRunning) { _, isRunning in
                syncEncodingLifecycle(phase: scenePhase, isRunning: isRunning)
            }
    }

    private func syncEncodingLifecycle(phase: ScenePhase, isRunning: Bool) {
        viewModel.suppressLiveDisplayUpdates = (phase == .background)
        #if os(iOS)
        if phase == .background && isRunning {
            encodingBackgroundTaskState.beginIfNeeded()
        } else {
            encodingBackgroundTaskState.endIfNeeded()
        }
        #elseif os(macOS)
        if phase == .background && isRunning {
            encodingNapMitigationState.beginIfNeeded()
        } else {
            encodingNapMitigationState.endIfNeeded()
        }
        #endif
    }
}

#if os(iOS)
/// Holds a `UIBackgroundTaskIdentifier` so expiration can end the task on the main queue without capturing `View` state.
private final class EncodingBackgroundTaskState {
    var taskID = UIBackgroundTaskIdentifier.invalid

    func endIfNeeded() {
        guard taskID != .invalid else { return }
        let id = taskID
        taskID = .invalid
        UIApplication.shared.endBackgroundTask(id)
    }

    func beginIfNeeded() {
        guard taskID == .invalid else { return }
        taskID = UIApplication.shared.beginBackgroundTask(withName: "GlyphEncoding") { [weak self] in
            DispatchQueue.main.async {
                self?.endIfNeeded()
            }
        }
    }
}
#endif

#if os(macOS)
private final class EncodingNapMitigationState {
    var activity: NSObjectProtocol?

    func endIfNeeded() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }

    func beginIfNeeded() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Glyph encoding")
    }
}
#endif
