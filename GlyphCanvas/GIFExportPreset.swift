//
//  GIFExportPreset.swift
//  GlyphCanvas
//

import Foundation

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
        }
    }

    /// Recommended long-edge resolution, FPS, frame count, and file size cap (bytes).
    var recommended: (resolution: Int, fps: Int, frameCount: Int, fileSizeCapBytes: Int) {
        switch self {
        case .iMessage:
            return (480, 15, 36, 3 * 1024 * 1024)
        case .discord:
            return (480, 12, 40, 8 * 1024 * 1024)
        case .slack:
            return (320, 8, 24, 2 * 1024 * 1024)
        case .xTwitter:
            return (600, 12, 35, 5 * 1024 * 1024)
        case .reddit:
            return (720, 12, 45, 20 * 1024 * 1024)
        case .emailSafe:
            return (256, 6, 20, 1 * 1024 * 1024)
        case .githubReadme:
            return (800, 8, 32, 5 * 1024 * 1024)
        case .tenorGiphy:
            return (480, 15, 40, 8 * 1024 * 1024)
        case .iosSticker:
            return (300, 15, 30, 512 * 1024)
        case .webEmbed:
            return (640, 12, 36, 4 * 1024 * 1024)
        }
    }
}
