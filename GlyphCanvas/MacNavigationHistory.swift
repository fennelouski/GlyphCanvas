//
//  MacNavigationHistory.swift
//  GlyphCanvas
//

import Combine
import Foundation

/// Owns tab selection and navigation paths for keyboard-driven back/forward (macOS).
final class MacNavigationHistory: ObservableObject {
    @Published var selectedTab: MainTab = .studio

    @Published var galleryPath: [AppRoute] = []
    private var galleryForward: [AppRoute] = []
    private var skipGalleryForwardClear = false

    @Published var studioPath: [StudioRoute] = []
    private var studioForward: [StudioRoute] = []
    private var skipStudioForwardClear = false

    func handleGalleryPathChange(from old: [AppRoute], to new: [AppRoute]) {
        if new.count > old.count {
            if !skipGalleryForwardClear {
                galleryForward.removeAll()
            }
        } else if new.count < old.count {
            let delta = old.count - new.count
            if delta == 1, let removed = old.last {
                galleryForward.append(removed)
            } else if delta > 1 {
                galleryForward.removeAll()
            }
        }
        skipGalleryForwardClear = false
    }

    func handleStudioPathChange(from old: [StudioRoute], to new: [StudioRoute]) {
        if new.count > old.count {
            if !skipStudioForwardClear {
                studioForward.removeAll()
            }
        } else if new.count < old.count {
            let delta = old.count - new.count
            if delta == 1, let removed = old.last {
                studioForward.append(removed)
            } else if delta > 1 {
                studioForward.removeAll()
            }
        }
        skipStudioForwardClear = false
    }

    func goBack() {
        switch selectedTab {
        case .gallery:
            guard !galleryPath.isEmpty else { return }
            galleryPath.removeLast()
        case .studio:
            guard !studioPath.isEmpty else { return }
            studioPath.removeLast()
        case .settings:
            break
        }
    }

    func goForward() {
        switch selectedTab {
        case .gallery:
            guard let route = galleryForward.popLast() else { return }
            skipGalleryForwardClear = true
            galleryPath.append(route)
        case .studio:
            guard let route = studioForward.popLast() else { return }
            skipStudioForwardClear = true
            studioPath.append(route)
        case .settings:
            break
        }
    }
}
