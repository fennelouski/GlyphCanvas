//
//  GalleryArchiveNaming.swift
//  GlyphCanvas
//

import Foundation

extension UUID {
    /// Deterministic 64-bit mix for stable UI labels across launches.
    fileprivate var galleryStableMix: UInt64 {
        let u = uuid
        let bytes: [UInt8] = [
            u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7,
            u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15
        ]
        var h: UInt64 = 14_695_981_039_346_656_037
        for b in bytes {
            h ^= UInt64(b)
            h &*= 1_099_511_628_211
        }
        return h
    }
}

enum GalleryArchiveNaming {
    private static let left = [
        "METROPOLITAN", "INDUSTRIAL", "NEON", "OBSIDIAN", "CHROME", "VOID",
        "PIXEL", "RASTER", "GRAPHITE", "CARBON", "SILICON", "PRISM"
    ]

    private static let right = [
        "SOUL", "PULSE", "MATRIX", "STRATA", "STATIC", "FRAME", "GHOST",
        "SHIFT", "DRIFT", "FIELD", "INDEX", "ECHO"
    ]

    static func compositionTitle(for id: UUID) -> String {
        let m = id.galleryStableMix
        let li = Int(m % UInt64(left.count))
        let ri = Int((m / UInt64(left.count)) % UInt64(right.count))
        return "\(left[li]) \(right[ri])"
    }

    /// Gallery-facing title: optional import-derived prefix plus the unique generated pair.
    static func displayTitle(titlePrefix: String?, for id: UUID) -> String {
        let unique = compositionTitle(for: id)
        if let p = titlePrefix?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            return "\(p) · \(unique)"
        }
        return unique
    }
}
