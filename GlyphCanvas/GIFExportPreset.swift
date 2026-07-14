//
//  GIFExportPreset.swift
//  GlyphCanvas
//

import Foundation

/// Output orientation / aspect ratio for a GIF export.
/// `.source` follows the artwork's own aspect ratio; fixed ratios letterbox/pillarbox the
/// artwork (fit-inside, centered, background-filled) so any source can be exported to that shape.
enum GIFExportAspect: String, CaseIterable, Identifiable, Sendable, Codable, Hashable {
    case source
    case portrait9x16

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .source: return "Match artwork"
        case .portrait9x16: return "Portrait 9:16"
        }
    }

    /// Fixed width:height ratio, or `nil` to follow the source artwork's aspect ratio.
    var ratio: (w: Int, h: Int)? {
        switch self {
        case .source: return nil
        case .portrait9x16: return (9, 16)
        }
    }

    /// For fixed ratios the `resolution` long-edge target drives the taller portrait edge.
    var isPortrait: Bool {
        switch self {
        case .source: return false
        case .portrait9x16: return true
        }
    }
}

/// Platform / utility presets for GIF export. Values are starting points; the constraint solver may tighten them.
enum GIFExportPreset: String, CaseIterable, Identifiable, Sendable, Codable {
    case iMessage
    case discord
    case slack
    case xTwitter
    case reddit
    case emailSafe
    case githubReadme
    case tenorGiphy
    case iosSticker
    case webEmbed
    case socialReel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iMessage: return "iMessage"
        case .discord: return "Discord"
        case .slack: return "Slack"
        case .xTwitter: return "X (Twitter)"
        case .reddit: return "Reddit"
        case .emailSafe: return "Email-safe"
        case .githubReadme: return "GitHub README"
        case .tenorGiphy: return "Tenor / GIPHY"
        case .iosSticker: return "iOS sticker-ish"
        case .webEmbed: return "Web embed"
        case .socialReel: return "TikTok / Reels (9:16)"
        }
    }

    /// Recommended long-edge resolution, FPS, frame count, file size cap (bytes), and output aspect.
    var recommended: (resolution: Int, fps: Int, frameCount: Int, fileSizeCapBytes: Int, aspect: GIFExportAspect) {
        switch self {
        case .iMessage:
            return (480, 15, 36, 3 * 1024 * 1024, .source)
        case .discord:
            return (480, 12, 40, 8 * 1024 * 1024, .source)
        case .slack:
            return (320, 8, 24, 2 * 1024 * 1024, .source)
        case .xTwitter:
            return (600, 12, 35, 5 * 1024 * 1024, .source)
        case .reddit:
            return (720, 12, 45, 20 * 1024 * 1024, .source)
        case .emailSafe:
            return (256, 6, 20, 1 * 1024 * 1024, .source)
        case .githubReadme:
            return (800, 8, 32, 5 * 1024 * 1024, .source)
        case .tenorGiphy:
            return (480, 15, 40, 8 * 1024 * 1024, .source)
        case .iosSticker:
            return (300, 15, 30, 512 * 1024, .source)
        case .webEmbed:
            return (640, 12, 36, 4 * 1024 * 1024, .source)
        case .socialReel:
            // Portrait 9:16 for TikTok / Instagram Reels. `resolution` is the tall edge (height);
            // width is derived as 9/16 of it (720 → 405×720). ~3s at 15fps; generous cap since
            // the encoder still enforces it.
            return (720, 15, 45, 15 * 1024 * 1024, .portrait9x16)
        }
    }
}
