//
//  GalleryTheme.swift
//  GlyphCanvas
//

import SwiftUI

enum GalleryTheme {
    /// Deep charcoal background (~#121212); landing hero.
    static let background = Color(red: 0.07, green: 0.07, blue: 0.07)
    /// Gallery grid page background (#0D0D0D).
    static let galleryScreenBackground = Color(red: 13.0 / 255.0, green: 13.0 / 255.0, blue: 13.0 / 255.0)
    /// Card surface (#1A1A1A).
    static let cardSurface = Color(red: 26.0 / 255.0, green: 26.0 / 255.0, blue: 26.0 / 255.0)
    /// Primary accent (#7EB1FF).
    static let accent = Color(red: 126.0 / 255.0, green: 177.0 / 255.0, blue: 1.0)
    /// Label on filled accent buttons.
    static let onAccentFill = Color(red: 0.05, green: 0.12, blue: 0.28)
    static let headline = Color.white
    static let bodyMuted = Color.white.opacity(0.62)
    static let secondaryButtonFill = Color.white.opacity(0.08)
    static let hudDetail = Color.white.opacity(0.38)
    static let hudAccent = Color(red: 0.92, green: 0.38, blue: 0.32)
    static let studioAccent = Color(red: 142.0 / 255.0, green: 185.0 / 255.0, blue: 1.0)
    static let studioStatusRed = Color(red: 1.0, green: 92.0 / 255.0, blue: 92.0 / 255.0)
    static let studioStroke = Color.white.opacity(0.18)

    static var marketingVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return v ?? "1.0"
    }

    // MARK: - Settings (Mechanical Editor mockup palette)

    /// Deep background (#0D1117).
    static let settingsScreenBackground = Color(red: 13.0 / 255.0, green: 17.0 / 255.0, blue: 23.0 / 255.0)
    /// Card surface (#161B22).
    static let settingsCardSurface = Color(red: 22.0 / 255.0, green: 27.0 / 255.0, blue: 34.0 / 255.0)
    /// Primary accent (#58A6FF).
    static let settingsAccent = Color(red: 88.0 / 255.0, green: 166.0 / 255.0, blue: 1.0)
    /// Danger accent (#F85149).
    static let settingsDanger = Color(red: 248.0 / 255.0, green: 81.0 / 255.0, blue: 73.0 / 255.0)
}
