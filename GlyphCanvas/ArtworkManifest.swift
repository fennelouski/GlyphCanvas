//
//  ArtworkManifest.swift
//  GlyphCanvas
//

import Foundation

/// On-disk artwork document (`manifest.json` beside `source.png`, `preview.png`, `thumb.png`).
struct ArtworkManifest: Sendable {
    static let currentVersion = 1

    var id: UUID
    var createdAt: Date
    /// Bump when the JSON shape changes.
    var formatVersion: Int
    var canvasWidth: Int
    var canvasHeight: Int
    var operations: [GlyphOperation]
    /// Human context for gallery titles (date, place, etc.); uniqueness is added in code via `GalleryArchiveNaming`.
    var titlePrefix: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        formatVersion: Int = Self.currentVersion,
        canvasWidth: Int,
        canvasHeight: Int,
        operations: [GlyphOperation],
        titlePrefix: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.formatVersion = formatVersion
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.operations = operations
        self.titlePrefix = titlePrefix
    }
}

extension ArtworkManifest: Equatable {
    nonisolated static func == (lhs: ArtworkManifest, rhs: ArtworkManifest) -> Bool {
        lhs.id == rhs.id &&
            lhs.createdAt == rhs.createdAt &&
            lhs.formatVersion == rhs.formatVersion &&
            lhs.canvasWidth == rhs.canvasWidth &&
            lhs.canvasHeight == rhs.canvasHeight &&
            lhs.operations == rhs.operations &&
            lhs.titlePrefix == rhs.titlePrefix
    }
}

extension ArtworkManifest: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, createdAt, formatVersion, canvasWidth, canvasHeight, operations, titlePrefix
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        canvasWidth = try c.decode(Int.self, forKey: .canvasWidth)
        canvasHeight = try c.decode(Int.self, forKey: .canvasHeight)
        operations = try c.decode([GlyphOperation].self, forKey: .operations)
        titlePrefix = try c.decodeIfPresent(String.self, forKey: .titlePrefix)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(formatVersion, forKey: .formatVersion)
        try c.encode(canvasWidth, forKey: .canvasWidth)
        try c.encode(canvasHeight, forKey: .canvasHeight)
        try c.encode(operations, forKey: .operations)
        try c.encodeIfPresent(titlePrefix, forKey: .titlePrefix)
    }
}

/// Lightweight row for `artworks-index.json`.
struct ArtworkIndexEntry: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var createdAt: Date
    var canvasWidth: Int
    var canvasHeight: Int
    /// Stored glyph count at last save (omitted in older index files → decoded as `0`).
    var glyphCount: Int
    var isFavorite: Bool
    var favoritedAt: Date?
    /// Mirrors `ArtworkManifest.titlePrefix` for gallery display without loading full manifests.
    var titlePrefix: String?

    enum CodingKeys: String, CodingKey {
        case id, createdAt, canvasWidth, canvasHeight, glyphCount, isFavorite, favoritedAt, titlePrefix
    }

    init(
        id: UUID,
        createdAt: Date,
        canvasWidth: Int,
        canvasHeight: Int,
        glyphCount: Int = 0,
        isFavorite: Bool = false,
        favoritedAt: Date? = nil,
        titlePrefix: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.glyphCount = glyphCount
        self.isFavorite = isFavorite
        self.favoritedAt = favoritedAt
        self.titlePrefix = titlePrefix
    }

    init(from manifest: ArtworkManifest) {
        self.id = manifest.id
        self.createdAt = manifest.createdAt
        self.canvasWidth = manifest.canvasWidth
        self.canvasHeight = manifest.canvasHeight
        self.glyphCount = manifest.operations.count
        self.isFavorite = false
        self.favoritedAt = nil
        self.titlePrefix = manifest.titlePrefix
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        canvasWidth = try c.decode(Int.self, forKey: .canvasWidth)
        canvasHeight = try c.decode(Int.self, forKey: .canvasHeight)
        glyphCount = try c.decodeIfPresent(Int.self, forKey: .glyphCount) ?? 0
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        favoritedAt = try c.decodeIfPresent(Date.self, forKey: .favoritedAt)
        titlePrefix = try c.decodeIfPresent(String.self, forKey: .titlePrefix)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(canvasWidth, forKey: .canvasWidth)
        try c.encode(canvasHeight, forKey: .canvasHeight)
        try c.encode(glyphCount, forKey: .glyphCount)
        try c.encode(isFavorite, forKey: .isFavorite)
        try c.encodeIfPresent(favoritedAt, forKey: .favoritedAt)
        try c.encodeIfPresent(titlePrefix, forKey: .titlePrefix)
    }
}

struct ArtworkIndexFile: Codable, Equatable, Sendable {
    var entries: [ArtworkIndexEntry]

    init(entries: [ArtworkIndexEntry] = []) {
        self.entries = entries
    }
}
