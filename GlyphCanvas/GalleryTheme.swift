//
//  GalleryTheme.swift
//  GlyphCanvas
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum GalleryTheme {
    /// Deep charcoal background in dark mode, near-white in light mode; landing hero.
    static let background = Color.adaptive(
        light: Color(red: 0.97, green: 0.97, blue: 0.97),
        dark: Color(red: 0.07, green: 0.07, blue: 0.07)
    )
    /// Gallery grid page background (#0D0D0D dark / near-white light).
    static let galleryScreenBackground = Color.adaptive(
        light: Color(red: 0.98, green: 0.98, blue: 0.98),
        dark: Color(red: 13.0 / 255.0, green: 13.0 / 255.0, blue: 13.0 / 255.0)
    )
    /// Card surface (#1A1A1A dark / white light).
    static let cardSurface = Color.adaptive(
        light: Color(red: 0.93, green: 0.93, blue: 0.93),
        dark: Color(red: 26.0 / 255.0, green: 26.0 / 255.0, blue: 26.0 / 255.0)
    )
    /// Primary accent (#7EB1FF).
    static let accent = Color(red: 126.0 / 255.0, green: 177.0 / 255.0, blue: 1.0)
    /// Label on filled accent buttons.
    static let onAccentFill = Color(red: 0.05, green: 0.12, blue: 0.28)
    static let headline = Color.adaptive(light: .black, dark: .white)
    static let bodyMuted = Color.adaptive(light: Color.black.opacity(0.6), dark: Color.white.opacity(0.62))
    static let secondaryButtonFill = Color.adaptive(light: Color.black.opacity(0.06), dark: Color.white.opacity(0.08))
    static let hudDetail = Color.adaptive(light: Color.black.opacity(0.45), dark: Color.white.opacity(0.38))
    static let hudAccent = Color(red: 0.92, green: 0.38, blue: 0.32)
    static let studioAccent = Color(red: 142.0 / 255.0, green: 185.0 / 255.0, blue: 1.0)
    static let studioStatusRed = Color(red: 1.0, green: 92.0 / 255.0, blue: 92.0 / 255.0)
    static let studioStroke = Color.adaptive(light: Color.black.opacity(0.15), dark: Color.white.opacity(0.18))

    static var marketingVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return v ?? "1.0"
    }

    // MARK: - Settings (Mechanical Editor mockup palette)

    /// Deep background (#0D1117 dark / near-white light).
    static let settingsScreenBackground = Color.adaptive(
        light: Color(red: 0.97, green: 0.97, blue: 0.98),
        dark: Color(red: 13.0 / 255.0, green: 17.0 / 255.0, blue: 23.0 / 255.0)
    )
    /// Card surface (#161B22 dark / white light).
    static let settingsCardSurface = Color.adaptive(
        light: Color(red: 0.93, green: 0.93, blue: 0.95),
        dark: Color(red: 22.0 / 255.0, green: 27.0 / 255.0, blue: 34.0 / 255.0)
    )
    /// Primary accent (#58A6FF).
    static let settingsAccent = Color(red: 88.0 / 255.0, green: 166.0 / 255.0, blue: 1.0)
    /// Danger accent (#F85149).
    static let settingsDanger = Color(red: 248.0 / 255.0, green: 81.0 / 255.0, blue: 73.0 / 255.0)
}

// MARK: - Adaptive color support

private extension Color {
    /// Produces a `Color` that resolves to `light` or `dark` based on the current
    /// system color scheme, so the app can follow the user's iOS/macOS appearance
    /// setting instead of being hardcoded to one palette.
    static func adaptive(light: Color, dark: Color) -> Color {
        #if os(iOS)
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif os(macOS)
        return Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        })
        #else
        return dark
        #endif
    }
}
