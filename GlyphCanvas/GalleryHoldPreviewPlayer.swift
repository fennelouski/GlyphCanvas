//
//  GalleryHoldPreviewPlayer.swift
//  GlyphCanvas
//

import Combine
import CoreGraphics
import Foundation
import SwiftUI

/// Drives a 6s hyperspeed glyph replay for gallery long-press preview (no `AppViewModel`).
@MainActor
final class GalleryHoldPreviewPlayer: ObservableObject {
    @Published private(set) var currentImage: CGImage?

    private let store = GlyphHistoryStore()
    private var playbackTask: Task<Void, Never>?

    func cancel() {
        playbackTask?.cancel()
        playbackTask = nil
        currentImage = nil
    }

    /// Begins replay from a blank canvas through full `operations` over 6 seconds, then holds the final frame until `cancel()`.
    func begin(library: ArtworkLibrary, artworkID: UUID) {
        cancel()
        playbackTask = Task {
            do {
                let manifest = try library.loadManifest(id: artworkID)
                let source = try library.loadSourceImage(id: artworkID)
                let canvasBG =
                    (try? ImageProcessing.darkestAmongTopFiveCommonColors(from: source))
                    ?? RGBAColor(r: 255, g: 255, b: 255, a: 255)
                try await self.store.importOperations(
                    manifest.operations,
                    width: manifest.canvasWidth,
                    height: manifest.canvasHeight,
                    canvasBackground: canvasBG
                )
                let count = manifest.operations.count
                let start = Date()
                while !Task.isCancelled {
                    let elapsed = Date().timeIntervalSince(start)
                    if elapsed >= 6.0 {
                        let img = try await self.store.render(upTo: count)
                        await MainActor.run { self.currentImage = img }
                        while !Task.isCancelled {
                            try await Task.sleep(nanoseconds: 50_000_000)
                        }
                        return
                    }
                    let idx: Int
                    if count == 0 {
                        idx = 0
                    } else {
                        let f = min(1.0, elapsed / 6.0)
                        idx = min(count, Int(round(f * Double(count))))
                    }
                    let img = try await self.store.render(upTo: idx)
                    await MainActor.run { self.currentImage = img }
                    try await Task.sleep(nanoseconds: 16_666_667)
                }
            } catch {
                await MainActor.run { self.currentImage = nil }
            }
        }
    }
}
