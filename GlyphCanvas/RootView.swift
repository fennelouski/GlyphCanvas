//
//  RootView.swift
//  GlyphCanvas
//

import SwiftUI

struct RootView: View {
    @StateObject private var library = ArtworkLibrary()
    @State private var selectedTab: MainTab = .studio
    @State private var studioAutoPresentImagePicker = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                GalleryView(
                    mainTab: $selectedTab,
                    studioAutoPresentImagePicker: $studioAutoPresentImagePicker
                )
                .environmentObject(library)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .detail(let id):
                        ArtworkDetailView(artworkId: id)
                            .environmentObject(library)
                    case .editorNew:
                        EditorView(resumeArtworkID: nil)
                            .environmentObject(library)
                    case .editorResume(let id):
                        EditorView(resumeArtworkID: id)
                            .environmentObject(library)
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

            NavigationStack {
                EditorView(
                    resumeArtworkID: nil,
                    autoPresentImagePicker: $studioAutoPresentImagePicker
                )
                    .environmentObject(library)
            }
            .tabItem {
                Label {
                    Text("STUDIO")
                } icon: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                }
            }
            .tag(MainTab.studio)

            NavigationStack {
                ProfileView()
                    .environmentObject(library)
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
        .tint(GalleryTheme.accent)
        .preferredColorScheme(.dark)
    }
}
