//
//  CharacterCaseMode.swift
//  GlyphCanvas
//

import Foundation

/// Keys for `@AppStorage` in `ContentView` (must stay stable for migration).
enum GlyphCanvasStorageKey {
    static let baseCharacterSet = "glyphCanvas.baseCharacterSet"
    static let characterCaseMode = "glyphCanvas.characterCaseMode"
    static let highDetailMode = "glyphCanvas.highDetailMode"
    static let autoArchive = "glyphCanvas.autoArchive"
    static let showSourceOverlay = "glyphCanvas.showSourceOverlay"
    /// Raw value of `OptimizationMode` (e.g. `greedy`, `genetic`).
    static let optimizationMode = "glyphCanvas.optimizationMode"
    static let debugOptimizationOverlay = "glyphCanvas.debugOptimizationOverlay"

    /// Matches `@AppStorage` default `true` when the key has never been written.
    static func highDetailModeEnabled() -> Bool {
        let k = Self.highDetailMode
        if UserDefaults.standard.object(forKey: k) == nil { return true }
        return UserDefaults.standard.bool(forKey: k)
    }

    static func autoArchiveEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Self.autoArchive)
    }

    static func clearAllGlyphCanvasKeys() {
        for key in [
            baseCharacterSet, characterCaseMode, highDetailMode, autoArchive,
            showSourceOverlay, optimizationMode, debugOptimizationOverlay
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

/// Default pool used for new installs, empty-input fallback, and `activeCharacterSet` recovery.
enum GlyphCanvasCharacterSetDefaults {
    static let baseString =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,:;!?@#&()"
}

enum CharacterCaseMode: String, CaseIterable, Sendable {
    case uppercase
    case both
    case lowercase

    /// Segmented control: icon only; accessibility strings describe behavior.
    var accessibilityLabel: String {
        switch self {
        case .uppercase: "Uppercase Only"
        case .both: "Uppercase and Lowercase"
        case .lowercase: "Lowercase Only"
        }
    }

    /// SF Symbols for the case filter. Lowercase uses `textformat.abc.dottedunderline` when available.
    var sfSymbolName: String {
        switch self {
        case .uppercase: "textformat.abc"
        case .both: "textformat"
        case .lowercase: "textformat.abc.dottedunderline"
        }
    }
}
