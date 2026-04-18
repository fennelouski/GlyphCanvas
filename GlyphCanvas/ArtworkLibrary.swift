//
//  ArtworkLibrary.swift
//  GlyphCanvas
//

import Combine
import CoreGraphics
import Foundation

/// Persists artwork folders and `artworks-index.json` under Application Support.
@MainActor
final class ArtworkLibrary: ObservableObject {
    static let thumbnailMaxDimension = 256

    static let manifestFilename = "manifest.json"
    static let sourcePNG = "source.png"
    static let previewPNG = "preview.png"
    static let thumbPNG = "thumb.png"
    static let indexFilename = "artworks-index.json"

    @Published private(set) var entries: [ArtworkIndexEntry] = []

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        do {
            try reloadFromDisk()
        } catch {
            entries = []
        }
    }

    private static var artworksRootURL: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bid = Bundle.main.bundleIdentifier ?? "GlyphCanvas"
        let base = appSupport.appendingPathComponent(bid, isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("Artworks", isDirectory: true)
    }

    var rootURL: URL { Self.artworksRootURL }

    private var indexURL: URL {
        Self.artworksRootURL.appendingPathComponent(Self.indexFilename)
    }

    func directoryURL(for id: UUID) -> URL {
        Self.artworksRootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func manifestURL(for id: UUID) -> URL {
        directoryURL(for: id).appendingPathComponent(Self.manifestFilename)
    }

    func sourceURL(for id: UUID) -> URL {
        directoryURL(for: id).appendingPathComponent(Self.sourcePNG)
    }

    func previewURL(for id: UUID) -> URL {
        directoryURL(for: id).appendingPathComponent(Self.previewPNG)
    }

    func thumbURL(for id: UUID) -> URL {
        directoryURL(for: id).appendingPathComponent(Self.thumbPNG)
    }

    /// Reloads index from disk (sorted newest first).
    func reloadFromDisk() throws {
        try FileManager.default.createDirectory(at: Self.artworksRootURL, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            entries = []
            return
        }
        let data = try Data(contentsOf: indexURL)
        let file = try decoder.decode(ArtworkIndexFile.self, from: data)
        entries = file.entries.sorted { $0.createdAt > $1.createdAt }
    }

    /// Writes manifest, PNGs, and updates the index. Returns the artwork id.
    /// Pass `existingArtworkID` to update the same gallery row; `createdAt` is preserved when a manifest already exists on disk.
    func saveArtwork(
        source: CGImage,
        preview: CGImage,
        operations: [GlyphOperation],
        existingArtworkID: UUID? = nil
    ) throws -> UUID {
        try FileManager.default.createDirectory(at: Self.artworksRootURL, withIntermediateDirectories: true)

        let w = source.width
        let h = source.height
        guard w == preview.width, h == preview.height else {
            throw ArtworkLibraryError.dimensionMismatch
        }

        let id = existingArtworkID ?? UUID()
        let manifestFileURL = manifestURL(for: id)
        let createdAt: Date
        if FileManager.default.fileExists(atPath: manifestFileURL.path),
           let existing = try? decoder.decode(ArtworkManifest.self, from: Data(contentsOf: manifestFileURL)),
           existing.id == id {
            createdAt = existing.createdAt
        } else {
            createdAt = Date()
        }

        let manifest = ArtworkManifest(
            id: id,
            createdAt: createdAt,
            canvasWidth: w,
            canvasHeight: h,
            operations: operations
        )
        let dir = directoryURL(for: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: manifestFileURL, options: [.atomic])

        guard let sourceData = PNGExport.data(from: source) else {
            throw ArtworkLibraryError.encodeFailure
        }
        try sourceData.write(to: sourceURL(for: id), options: [.atomic])

        guard let previewData = PNGExport.data(from: preview) else {
            throw ArtworkLibraryError.encodeFailure
        }
        try previewData.write(to: previewURL(for: id), options: [.atomic])

        let thumbImage = try ImageProcessing.downscaledImage(preview, maxDimension: Self.thumbnailMaxDimension)
        guard let thumbData = PNGExport.data(from: thumbImage) else {
            throw ArtworkLibraryError.encodeFailure
        }
        try thumbData.write(to: thumbURL(for: id), options: [.atomic])

        var next = entries.filter { $0.id != id }
        next.append(ArtworkIndexEntry(from: manifest))
        entries = next.sorted { $0.createdAt > $1.createdAt }
        try persistIndex()
        return id
    }

    func loadManifest(id: UUID) throws -> ArtworkManifest {
        let data = try Data(contentsOf: manifestURL(for: id))
        let m = try decoder.decode(ArtworkManifest.self, from: data)
        guard m.id == id else {
            throw ArtworkLibraryError.invalidManifest
        }
        guard m.formatVersion == ArtworkManifest.currentVersion else {
            throw ArtworkLibraryError.unsupportedVersion
        }
        return m
    }

    func loadSourceImage(id: UUID) throws -> CGImage {
        let data = try Data(contentsOf: sourceURL(for: id))
        guard let img = ImageProcessing.decodeCGImage(data: data) else {
            throw ArtworkLibraryError.decodeFailure
        }
        return img
    }

    func deleteArtwork(id: UUID) throws {
        let dir = directoryURL(for: id)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        entries.removeAll { $0.id == id }
        try persistIndex()
    }

    /// Removes all artwork folders and clears the on-disk index.
    func deleteAllArtworks() throws {
        let root = Self.artworksRootURL
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        entries = []
        try persistIndex()
    }

    private func persistIndex() throws {
        let file = ArtworkIndexFile(entries: entries)
        let data = try encoder.encode(file)
        try data.write(to: indexURL, options: [.atomic])
    }
}

enum ArtworkLibraryError: Error {
    case dimensionMismatch
    case encodeFailure
    case decodeFailure
    case invalidManifest
    case unsupportedVersion
}
