//
//  CharacterCaseMode.swift
//  GlyphCanvas
//

import Foundation

/// Keys for `@AppStorage` in `ContentView` (must stay stable for migration).
enum GlyphCanvasStorageKey {
    static let baseCharacterSet = "glyphCanvas.baseCharacterSet"
    static let stampSourceMode = "glyphCanvas.stampSourceMode"
    static let characterCaseMode = "glyphCanvas.characterCaseMode"
    static let highDetailMode = "glyphCanvas.highDetailMode"
    static let autoArchive = "glyphCanvas.autoArchive"
    static let showSourceOverlay = "glyphCanvas.showSourceOverlay"
    /// Raw value of `OptimizationMode` (e.g. `greedy`, `genetic`).
    static let optimizationMode = "glyphCanvas.optimizationMode"
    /// Raw value of `EncodingComparisonMode` (e.g. `perceptual`, `edges`).
    static let encodingComparisonMode = "glyphCanvas.encodingComparisonMode"
    static let debugOptimizationOverlay = "glyphCanvas.debugOptimizationOverlay"
    /// 1...8 where 8 means highest color fidelity (least quantization).
    static let colorFidelity = "glyphCanvas.colorFidelity"
    static let recentStampSets = "glyphCanvas.recentStampSets"

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
            baseCharacterSet, stampSourceMode, characterCaseMode, highDetailMode, autoArchive,
            showSourceOverlay, optimizationMode, encodingComparisonMode, debugOptimizationOverlay,
            colorFidelity, recentStampSets
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

/// Whether stamps are built from individual characters or from unique words in pasted text.
enum StampSourceMode: String, CaseIterable, Sendable, Codable {
    case characters
    case words

    var displayLabel: String {
        switch self {
        case .characters: "Characters"
        case .words: "Words"
        }
    }
}

/// Default pool used for new installs, empty-input fallback, and `activeStamps` recovery.
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

// MARK: - Stamp set (characters vs words + case filter)

/// Centralized pipeline so `activeStamps` and density bucketing stay consistent.
enum StampSetPipeline {
    /// Applies case rules to letters only; preserves order; first-seen wins for duplicates. Emits one-element strings.
    static func filteredOrderedUniqueCharacters(from raw: String, mode: CharacterCaseMode) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        var out: [String] = []
        out.reserveCapacity(trimmed.count)
        for ch in trimmed {
            let keep: Bool
            if ch.isLetter {
                switch mode {
                case .uppercase: keep = ch.isUppercase
                case .lowercase: keep = ch.isLowercase
                case .both: keep = true
                }
            } else {
                keep = true
            }
            let s = String(ch)
            guard keep, seen.insert(s).inserted else { continue }
            out.append(s)
        }
        return out
    }

    /// Splits on whitespace, strips outer punctuation, keeps apostrophes inside words; dedupes in first-seen order.
    static func filteredOrderedUniqueWords(from raw: String, mode: CharacterCaseMode) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for segment in raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            guard let w = normalizeWordToken(String(segment), mode: mode), !w.isEmpty else { continue }
            guard seen.insert(w).inserted else { continue }
            out.append(w)
        }
        return out
    }

    /// Active stamp list for encoding; falls back to default character set if empty.
    static func activeSet(base: String, mode: CharacterCaseMode, source: StampSourceMode) -> [String] {
        let first: [String]
        switch source {
        case .characters:
            first = filteredOrderedUniqueCharacters(from: base, mode: mode)
        case .words:
            first = filteredOrderedUniqueWords(from: base, mode: mode)
        }
        if !first.isEmpty { return first }
        return filteredOrderedUniqueCharacters(from: GlyphCanvasCharacterSetDefaults.baseString, mode: mode)
    }

    /// True when user input yields no stamps before fallback.
    static func isEffectivelyEmpty(base: String, mode: CharacterCaseMode, source: StampSourceMode) -> Bool {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        switch source {
        case .characters:
            return filteredOrderedUniqueCharacters(from: base, mode: mode).isEmpty
        case .words:
            return filteredOrderedUniqueWords(from: base, mode: mode).isEmpty
        }
    }

    private static let asciiApostrophe: Character = "'"
    private static let unicodeApostrophe: Character = "\u{2019}"

    private static func isInnerWordCharacter(_ c: Character) -> Bool {
        if c.isLetter || c.isNumber || c == asciiApostrophe || c == unicodeApostrophe { return true }
        return c.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.properties.isEmoji }
    }

    /// Anything that is not a letter, digit, apostrophe, or emoji is stripped from word edges.
    private static func isStrippableEdgePunctuation(_ c: Character) -> Bool {
        !isInnerWordCharacter(c)
    }

    /// Strips leading/trailing punctuation and symbols, but never strips apostrophes (possessives / contractions).
    private static func stripOuterPunctuation(from word: String) -> String {
        var chars = Array(word)
        while let c = chars.first {
            if isStrippableEdgePunctuation(c) {
                chars.removeFirst()
                continue
            }
            break
        }
        while let c = chars.last {
            if isStrippableEdgePunctuation(c) {
                chars.removeLast()
                continue
            }
            break
        }
        return String(chars)
    }

    private static func normalizeWordToken(_ raw: String, mode: CharacterCaseMode) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let outer = stripOuterPunctuation(from: trimmed)
        guard !outer.isEmpty else { return nil }
        let inner = String(outer.filter { isInnerWordCharacter($0) })
        guard !inner.isEmpty else { return nil }
        switch mode {
        case .uppercase: return inner.uppercased()
        case .lowercase: return inner.lowercased()
        case .both: return inner
        }
    }
}

struct RecentStampSet: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let fingerprint: String
    let sourceMode: StampSourceMode
    let rawInput: String
    let displayLabel: String
    let stampCount: Int
    let updatedAt: Date
}

enum RecentStampSetStore {
    static let maxItems = 10

    static func decode(from json: String) -> [RecentStampSet] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([RecentStampSet].self, from: data)
        } catch {
            return []
        }
    }

    static func encode(_ items: [RecentStampSet]) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            return String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            return "[]"
        }
    }

    static func makeRecent(
        base: String,
        mode: CharacterCaseMode,
        source: StampSourceMode,
        now: Date = Date()
    ) -> RecentStampSet? {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !StampSetPipeline.isEffectivelyEmpty(base: base, mode: mode, source: source) else { return nil }
        let stamps = StampSetPipeline.activeSet(base: base, mode: mode, source: source)
        guard !stamps.isEmpty else { return nil }
        let normalized = normalizedInput(base: base, mode: mode, source: source)
        let fingerprint = makeFingerprint(normalized: normalized, source: source)
        return RecentStampSet(
            id: fingerprint,
            fingerprint: fingerprint,
            sourceMode: source,
            rawInput: base,
            displayLabel: makeDisplayLabel(stamps: stamps, source: source),
            stampCount: stamps.count,
            updatedAt: now
        )
    }

    static func upsert(_ recent: RecentStampSet, into existing: [RecentStampSet], limit: Int = maxItems) -> [RecentStampSet] {
        var out: [RecentStampSet] = [recent]
        out.reserveCapacity(min(limit, existing.count + 1))
        for item in existing where item.fingerprint != recent.fingerprint {
            guard out.count < limit else { break }
            out.append(item)
        }
        return out
    }

    private static func normalizedInput(base: String, mode: CharacterCaseMode, source: StampSourceMode) -> String {
        switch source {
        case .characters:
            return StampSetPipeline.filteredOrderedUniqueCharacters(from: base, mode: mode).joined(separator: "\u{1F}")
        case .words:
            return StampSetPipeline.filteredOrderedUniqueWords(from: base, mode: mode).joined(separator: "\u{1F}")
        }
    }

    private static func makeFingerprint(normalized: String, source: StampSourceMode) -> String {
        "\(source.rawValue)::\(normalized)"
    }

    private static func makeDisplayLabel(stamps: [String], source: StampSourceMode) -> String {
        switch source {
        case .characters:
            let snippet = stamps.joined().prefix(20)
            return String(snippet)
        case .words:
            let preview = stamps.prefix(4).joined(separator: " ")
            return preview
        }
    }
}
