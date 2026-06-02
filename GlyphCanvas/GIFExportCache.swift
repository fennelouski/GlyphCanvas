//
//  GIFExportCache.swift
//  GlyphCanvas
//

import Foundation

/// Sidecar payload (JSON via `JSONSerialization`, avoids Swift 6 `Codable` / actor isolation issues).
private struct GIFExportCacheEntry: Sendable {
    var createdAt: Date
    var manifestId: UUID
    /// Same value as `GIFExportConfig.cacheKeyHash(manifest:)` used for the file basename.
    var cacheKeyHash: String
}

private enum GIFExportCacheCodec {
    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated static func decode(_ data: Data) throws -> GIFExportCacheEntry {
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let dict = obj as? [String: Any],
              let createdStr = dict["createdAt"] as? String,
              let created = iso8601.date(from: createdStr),
              let idStr = dict["manifestId"] as? String,
              let manifestId = UUID(uuidString: idStr),
              let cacheKeyHash = dict["cacheKeyHash"] as? String
        else {
            throw NSError(domain: "GIFExportCache", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid sidecar JSON."])
        }
        return GIFExportCacheEntry(createdAt: created, manifestId: manifestId, cacheKeyHash: cacheKeyHash)
    }

    nonisolated static func encode(_ entry: GIFExportCacheEntry) throws -> Data {
        let dict: [String: Any] = [
            "createdAt": iso8601.string(from: entry.createdAt),
            "manifestId": entry.manifestId.uuidString,
            "cacheKeyHash": entry.cacheKeyHash,
        ]
        return try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
    }
}

actor GIFExportCache {
    static let shared = GIFExportCache()

    private static var cacheRootURL: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bid = Bundle.main.bundleIdentifier ?? "GlyphCanvas"
        let base = appSupport.appendingPathComponent(bid, isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        let root = base.appendingPathComponent("GIFCache", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func gifURL(hash: String) -> URL {
        Self.cacheRootURL.appendingPathComponent("\(hash).gif", isDirectory: false)
    }

    private func jsonURL(hash: String) -> URL {
        Self.cacheRootURL.appendingPathComponent("\(hash).json", isDirectory: false)
    }

    /// Returns file URL if a valid cached GIF exists for this manifest + config.
    func lookup(manifest: ArtworkManifest, config: GIFExportConfig) -> URL? {
        let hash = config.cacheKeyHash(manifest: manifest)
        let gif = gifURL(hash: hash)
        let side = jsonURL(hash: hash)
        guard FileManager.default.fileExists(atPath: gif.path) else { return nil }
        guard let data = try? Data(contentsOf: side),
              let entry = try? GIFExportCacheCodec.decode(data),
              entry.manifestId == manifest.id,
              entry.cacheKeyHash == hash
        else {
            return nil
        }
        return gif
    }

    /// Writes GIF bytes and sidecar; returns URL of the GIF.
    func store(data: Data, manifest: ArtworkManifest, config: GIFExportConfig) throws -> URL {
        let hash = config.cacheKeyHash(manifest: manifest)
        let gif = gifURL(hash: hash)
        let side = jsonURL(hash: hash)
        let entry = GIFExportCacheEntry(createdAt: Date(), manifestId: manifest.id, cacheKeyHash: hash)
        let meta = try GIFExportCacheCodec.encode(entry)
        try data.write(to: gif, options: .atomic)
        try meta.write(to: side, options: .atomic)
        return gif
    }

    /// Deletes cached pairs older than `maxAge` (default 30 days).
    func pruneExpired(now: Date = Date(), maxAge: TimeInterval = 30 * 24 * 60 * 60) {
        let fm = FileManager.default
        let root = Self.cacheRootURL
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return }
        for name in names where name.hasSuffix(".json") {
            let jsonPath = root.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: jsonPath),
                  let entry = try? GIFExportCacheCodec.decode(data)
            else { continue }
            if now.timeIntervalSince(entry.createdAt) <= maxAge { continue }
            let base = String(name.dropLast(5))
            let gifPath = root.appendingPathComponent("\(base).gif")
            try? fm.removeItem(at: jsonPath)
            try? fm.removeItem(at: gifPath)
        }
    }
}
