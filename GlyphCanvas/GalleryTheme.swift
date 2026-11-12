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
    // Theme-dependent colors (backgrounds, surfaces, accent) live on `AppTheme`;
    // read them via `@Environment(\.appTheme)` so views redraw when the theme changes.

    /// Label on filled accent buttons.
    static let onAccentFill = Color.adaptive(light: .white, dark: Color(red: 0.05, green: 0.12, blue: 0.28))
    static let headline = Color.adaptive(light: .black, dark: .white)
    static let bodyMuted = Color.adaptive(light: Color.black.opacity(0.6), dark: Color.white.opacity(0.7))
    static let secondaryButtonFill = Color.adaptive(light: Color.black.opacity(0.06), dark: Color.white.opacity(0.1))
    static let hudDetail = Color.adaptive(light: Color.black.opacity(0.45), dark: Color.white.opacity(0.5))
    static let hudAccent = Color(red: 0.92, green: 0.38, blue: 0.32)
    static let studioStatusRed = Color(red: 1.0, green: 92.0 / 255.0, blue: 92.0 / 255.0)
    static let studioStroke = Color.adaptive(light: Color.black.opacity(0.15), dark: Color.white.opacity(0.18))

    static var marketingVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return v ?? "1.0"
    }

    /// Danger accent (#F85149).
    static let settingsDanger = Color(red: 248.0 / 255.0, green: 81.0 / 255.0, blue: 73.0 / 255.0)
}

// MARK: - Selectable themes

enum AppTheme: String, CaseIterable, Identifiable {
    case aurora, sunset, ocean, meadow, graphite

    var id: String { rawValue }

    static let storageKey = "glyphCanvas.appTheme"

    var title: String {
        switch self {
        case .aurora: "Aurora"
        case .sunset: "Sunset"
        case .ocean: "Ocean"
        case .meadow: "Meadow"
        case .graphite: "Graphite"
        }
    }

    private struct Palette {
        // Screen gradient (top-leading -> bottom-trailing) and accent, per appearance.
        var darkTop: Color, darkBottom: Color, lightTop: Color, lightBottom: Color
        var darkAccent: Color, lightAccent: Color
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }

    private var palette: Palette {
        let c = Self.rgb
        switch self {
        case .aurora:
            return Palette(darkTop: c(64, 30, 120), darkBottom: c(10, 82, 96),
                           lightTop: c(236, 226, 255), lightBottom: c(214, 246, 240),
                           darkAccent: c(110, 240, 205), lightAccent: c(108, 52, 200))
        case .sunset:
            return Palette(darkTop: c(118, 24, 92), darkBottom: c(160, 66, 30),
                           lightTop: c(255, 226, 232), lightBottom: c(255, 240, 210),
                           darkAccent: c(255, 205, 90), lightAccent: c(214, 72, 52))
        case .ocean:
            return Palette(darkTop: c(12, 50, 120), darkBottom: c(6, 100, 124),
                           lightTop: c(220, 236, 255), lightBottom: c(214, 248, 250),
                           darkAccent: c(120, 225, 255), lightAccent: c(0, 104, 184))
        case .meadow:
            return Palette(darkTop: c(20, 84, 58), darkBottom: c(84, 100, 22),
                           lightTop: c(226, 248, 222), lightBottom: c(250, 248, 212),
                           darkAccent: c(214, 255, 110), lightAccent: c(36, 128, 52))
        case .graphite:
            // The original near-black look.
            return Palette(darkTop: c(18, 18, 18), darkBottom: c(13, 13, 13),
                           lightTop: c(248, 248, 248), lightBottom: c(250, 250, 250),
                           darkAccent: c(126, 177, 255), lightAccent: c(33, 92, 199))
        }
    }

    var accent: Color { .adaptive(light: palette.lightAccent, dark: palette.darkAccent) }
    var gradientTop: Color { .adaptive(light: palette.lightTop, dark: palette.darkTop) }
    var gradientBottom: Color { .adaptive(light: palette.lightBottom, dark: palette.darkBottom) }

    /// Full-screen background for every main page.
    var screenBackground: LinearGradient {
        LinearGradient(colors: [gradientTop, gradientBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Cards float on the gradient as frosted tints rather than opaque grey slabs.
    var cardSurface: Color {
        self == .graphite
            ? .adaptive(light: Color(white: 0.93), dark: Color(white: 26.0 / 255))
            : .adaptive(light: Color.white.opacity(0.7), dark: Color.white.opacity(0.11))
    }

    /// Backdrop behind the live canvas.
    var canvasBackdrop: Color {
        .adaptive(light: Color.black.opacity(0.06), dark: Color.black.opacity(self == .graphite ? 0.4 : 0.22))
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.aurora
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

// MARK: - Adaptive color support

extension Color {
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
