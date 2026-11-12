//
//  RootView.swift
//  GlyphCanvas
//

import SwiftUI

struct RootView: View {
    @StateObject private var library = ArtworkLibrary()
    @StateObject private var navigationHistory = MacNavigationHistory()
    @State private var studioAutoPresentImagePicker = false
    @State private var scheduledGIFCachePrune = false
    @AppStorage(AppTheme.storageKey) private var storedTheme = AppTheme.aurora.rawValue

    private var theme: AppTheme { AppTheme(rawValue: storedTheme) ?? .aurora }

    var body: some View {
        tabContainer
            .environmentObject(library)
            .environmentObject(navigationHistory)
            .environment(\.appTheme, theme)
            .onChange(of: navigationHistory.galleryPath) { old, new in
                navigationHistory.handleGalleryPathChange(from: old, to: new)
            }
            .onChange(of: navigationHistory.studioPath) { old, new in
                navigationHistory.handleStudioPathChange(from: old, to: new)
            }
            #if DEBUG
            .onAppear {
                // Screenshot / UI-test hook: `-debugTab studio|settings|gallery`.
                if let raw = UserDefaults.standard.string(forKey: "debugTab"), let tab = MainTab(rawValue: raw) {
                    navigationHistory.selectedTab = tab
                }
            }
            #endif
            .task {
                guard !scheduledGIFCachePrune else { return }
                scheduledGIFCachePrune = true
                try? await Task.sleep(for: .seconds(90))
                await GIFExportCache.shared.pruneExpired()
            }
            #if os(macOS)
            .onKeyPress(KeyEquivalent("["), phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                navigationHistory.goBack()
                return .handled
            }
            .onKeyPress(KeyEquivalent("]"), phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                navigationHistory.goForward()
                return .handled
            }
            #endif
    }

    private var tabContainer: some View {
        TabView(selection: $navigationHistory.selectedTab) {
            Tab("Home", systemImage: "house", value: MainTab.gallery) {
                GalleryTabRoot(studioAutoPresentImagePicker: $studioAutoPresentImagePicker)
            }
            Tab("Studio", systemImage: "character.textbox", value: MainTab.studio) {
                StudioTabRoot(studioAutoPresentImagePicker: $studioAutoPresentImagePicker)
            }
            Tab("Transitions", systemImage: "film.stack", value: MainTab.transitions) {
                VideoTransitionView()
            }
            Tab("Settings", systemImage: "gearshape", value: MainTab.settings) {
                NavigationStack { ProfileView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(theme.accent)
    }
}

// MARK: - Tab roots (split for Swift type checking)

private struct GalleryTabRoot: View {
    @EnvironmentObject private var navigationHistory: MacNavigationHistory
    @Binding var studioAutoPresentImagePicker: Bool

    var body: some View {
        NavigationStack(path: $navigationHistory.galleryPath) {
            GalleryView(
                mainTab: $navigationHistory.selectedTab,
                studioAutoPresentImagePicker: $studioAutoPresentImagePicker
            )
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .detail(let id):
                    ArtworkDetailView(artworkId: id)
                case .editorNew:
                    EditorView(resumeArtworkID: nil)
                case .editorResume(let id):
                    EditorView(resumeArtworkID: id)
                }
            }
        }
    }
}

private struct StudioTabRoot: View {
    @EnvironmentObject private var navigationHistory: MacNavigationHistory
    @Binding var studioAutoPresentImagePicker: Bool

    var body: some View {
        NavigationStack(path: $navigationHistory.studioPath) {
            EditorView(
                resumeArtworkID: nil,
                autoPresentImagePicker: $studioAutoPresentImagePicker
            )
        }
    }
}
