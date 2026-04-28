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
    #if os(macOS)
    private static let studioToolbarTrailingPlacement = ToolbarItemPlacement.primaryAction
    #else
    private static let studioToolbarTrailingPlacement = ToolbarItemPlacement.topBarTrailing
    #endif

    let resumeArtworkID: UUID?
    var autoPresentImagePicker: Binding<Bool>? = nil
    /// When set (e.g. Studio tab), toolbar matches phone mock: grid → Gallery, sliders → controls.
    var mainTab: Binding<MainTab>? = nil

    @StateObject private var viewModel = AppViewModel()
    @State private var jumpToReviewSection = false
    @EnvironmentObject private var library: ArtworkLibrary
    @Environment(\.scenePhase) private var scenePhase

    #if os(iOS)
    @State private var encodingBackgroundTaskState = EncodingBackgroundTaskState()
    #elseif os(macOS)
    @State private var encodingNapMitigationState = EncodingNapMitigationState()
    #endif

    var body: some View {
        ContentView(viewModel: viewModel, autoPresentImagePicker: autoPresentImagePicker, jumpToReviewSection: $jumpToReviewSection)
            .toolbar {
#if os(iOS)
                if let mainTab {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            mainTab.wrappedValue = .gallery
                        } label: {
                            Image(systemName: "square.grid.2x2")
                                .foregroundStyle(GalleryTheme.hudDetail)
                        }
                        .accessibilityLabel("Gallery")
                    }
                    ToolbarItem(placement: .principal) {
                        Text("STUDIO")
                            .font(.subheadline.weight(.heavy))
                            .tracking(1.2)
                            .foregroundStyle(GalleryTheme.studioAccent)
                    }
                    ToolbarItem(placement: Self.studioToolbarTrailingPlacement) {
                        Button {
                            jumpToReviewSection = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(GalleryTheme.hudDetail)
                        }
                        .accessibilityLabel("Review, export, and advanced")
                    }
                } else {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                            Text("STUDIO_SESSION")
                                .font(.subheadline.weight(.heavy))
                                .tracking(1.0)
                        }
                        .foregroundStyle(GalleryTheme.studioAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    ToolbarItemGroup(placement: Self.studioToolbarTrailingPlacement) {
                        Button {
                            jumpToReviewSection = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .accessibilityLabel("Review, export, and advanced")
                        NavigationLink(value: StudioRoute.profile) {
                            Image(systemName: "person.crop.circle.fill")
                        }
                    }
                }
#else
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                        Text("STUDIO_SESSION")
                            .font(.subheadline.weight(.heavy))
                            .tracking(1.0)
                    }
                    .foregroundStyle(GalleryTheme.studioAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                ToolbarItemGroup(placement: Self.studioToolbarTrailingPlacement) {
                    Button {
                        jumpToReviewSection = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("Review, export, and advanced")
                    NavigationLink(value: StudioRoute.profile) {
                        Image(systemName: "person.crop.circle.fill")
                    }
                }
#endif
            }
            .navigationTitle("")
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
            .background(GalleryTheme.galleryScreenBackground)
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
