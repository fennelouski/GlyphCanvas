//
//  PNGExportPlatform.swift
//  GlyphCanvas
//

import Foundation

#if os(iOS)
import Photos
#endif
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// User cancelled the macOS save panel (not an error to surface as a failure banner).
struct PNGExportUserCancelled: Error {}

enum PNGExportPlatform {
    /// Saves PNG data to Photos (iOS) or via save panel (macOS).
    /// - Returns: `.success(message)` on write, `.failure` for denial/errors; macOS cancel → `PNGExportUserCancelled`.
    static func save(data: Data, suggestedFilename: String) async -> Result<String, Error> {
        #if os(iOS)
        await saveToPhotos(data: data)
        #elseif os(macOS)
        await saveWithPanel(data: data, suggestedFilename: suggestedFilename)
        #else
        .failure(NSError(domain: "GlyphCanvas", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported platform."]))
        #endif
    }

    /// Saves animated GIF data to Photos (iOS) or via save panel (macOS).
    static func saveGIF(data: Data, suggestedFilename: String) async -> Result<String, Error> {
        #if os(iOS)
        await saveGIFToPhotos(data: data)
        #elseif os(macOS)
        await saveGIFWithPanel(data: data, suggestedFilename: suggestedFilename)
        #else
        .failure(NSError(domain: "GlyphCanvas", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported platform."]))
        #endif
    }

    #if os(iOS)
    private static func saveToPhotos(data: Data) async -> Result<String, Error> {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            return .failure(NSError(domain: "GlyphCanvas", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photos access denied."]))
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlyphCanvas-\(UUID().uuidString).png")
        do {
            try data.write(to: temp)
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: temp)
            }
            try? FileManager.default.removeItem(at: temp)
            return .success("Saved to Photos.")
        } catch {
            try? FileManager.default.removeItem(at: temp)
            return .failure(error)
        }
    }

    private static func saveGIFToPhotos(data: Data) async -> Result<String, Error> {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            return .failure(NSError(domain: "GlyphCanvas", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photos access denied."]))
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlyphCanvas-\(UUID().uuidString).gif")
        do {
            try data.write(to: temp)
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: temp, options: nil)
            }
            try? FileManager.default.removeItem(at: temp)
            return .success("Saved GIF to Photos.")
        } catch {
            try? FileManager.default.removeItem(at: temp)
            return .failure(error)
        }
    }
    #endif

    #if os(macOS)
    private static func saveWithPanel(data: Data, suggestedFilename: String) async -> Result<String, Error> {
        await MainActor.run {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = suggestedFilename
            guard panel.runModal() == .OK, let url = panel.url else {
                return .failure(PNGExportUserCancelled())
            }
            do {
                try data.write(to: url)
                return .success("Saved.")
            } catch {
                return .failure(error)
            }
        }
    }

    private static func saveGIFWithPanel(data: Data, suggestedFilename: String) async -> Result<String, Error> {
        await MainActor.run {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.gif]
            panel.nameFieldStringValue = suggestedFilename.hasSuffix(".gif") ? suggestedFilename : "\(suggestedFilename).gif"
            guard panel.runModal() == .OK, let url = panel.url else {
                return .failure(PNGExportUserCancelled())
            }
            do {
                try data.write(to: url)
                return .success("Saved.")
            } catch {
                return .failure(error)
            }
        }
    }
    #endif
}
