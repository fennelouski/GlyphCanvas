//
//  RootView.swift
//  GlyphCanvas
//

import SwiftUI

struct RootView: View {
    @StateObject private var library = ArtworkLibrary()
    @StateObject private var navigationHistory = MacNavigationHistory()
    @State private var studioAutoPresentImagePicker = false

    var body: some View {
        tabContainer
            .environmentObject(library)
            .environmentObject(navigationHistory)
            .onChange(of: navigationHistory.galleryPath) { old, new in
                navigationHistory.handleGalleryPathChange(from: old, to: new)
            }
            .onChange(of: navigationHistory.studioPath) { old, new in
                navigationHistory.handleStudioPathChange(from: old, to: new)
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
            GalleryTabRoot(studioAutoPresentImagePicker: $studioAutoPresentImagePicker)
            StudioTabRoot(studioAutoPresentImagePicker: $studioAutoPresentImagePicker)
            SettingsTabRoot()
        }
        .tint(GalleryTheme.accent)
        .preferredColorScheme(.dark)
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
        .tabItem {
            Label {
                Text("GALLERY")
            } icon: {
                Image(systemName: "square.grid.2x2")
            }
        }
        .tag(MainTab.gallery)
    }
}

private struct StudioTabRoot: View {
    @EnvironmentObject private var navigationHistory: MacNavigationHistory
    @Binding var studioAutoPresentImagePicker: Bool

    var body: some View {
        NavigationStack(path: $navigationHistory.studioPath) {
            EditorView(
                resumeArtworkID: nil,
                autoPresentImagePicker: $studioAutoPresentImagePicker,
                mainTab: $navigationHistory.selectedTab
            )
        }
        .tabItem {
            Label {
                Text("STUDIO")
            } icon: {
                Image(systemName: "keyboard")
            }
        }
        .tag(MainTab.studio)
    }
}

private struct SettingsTabRoot: View {
    var body: some View {
        NavigationStack {
            ProfileView()
        }
        .tabItem {
            Label {
                Text("SETTINGS")
            } icon: {
                Image(systemName: "gearshape.fill")
            }
        }
        .tag(MainTab.settings)
    }
}
