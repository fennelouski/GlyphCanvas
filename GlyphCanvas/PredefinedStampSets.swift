//
//  PredefinedStampSets.swift
//  GlyphCanvas
//

import Foundation

/// Built-in character pools for **character** stamp mode (append into the user’s set without reordering existing stamps).
enum PredefinedStampSets {
    static let uppercaseLetters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    static let lowercaseLetters = "abcdefghijklmnopqrstuvwxyz"
    static let digits = "0123456789"
    /// Aligned with `ImageProcessing.candidateCharacters` punctuation-style symbols (ASCII).
    static let punctuation = ".,:;!?@#$%&*+-=/\\|()[]{}\"'`"
    /// Curated common emoji; expand or replace with a larger list over time.
    static let emoji =
        "😀😃😄😁😆🥹😂🤣🥲☺️😊😍🤩😘🥰😇🙂😉🫠🫡🤔🤐😐😶🙄😏😮🤯😳🥵🥶😱😭😢😤😡💀👍👎✌️🙏👏🙌💪❤️🔥⭐✨💯🎉🎊✅❌❓❗️🐶🐱🌙☀️🌈☁️🍎🍕☕️"

    /// Appends characters from `preset` that are not already in `base` (preserves `base` order, then new chars in preset order).
    static func mergeAppendingUnique(into base: inout String, preset: String) {
        var seen = Set<Character>()
        for ch in base {
            seen.insert(ch)
        }
        for ch in preset where seen.insert(ch).inserted {
            base.append(ch)
        }
    }
}
