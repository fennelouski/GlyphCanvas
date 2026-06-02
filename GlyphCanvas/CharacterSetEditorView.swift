//
//  CharacterSetEditorView.swift
//  GlyphCanvas
//

import SwiftUI

struct CharacterSetEditorView: View {
    @AppStorage(GlyphCanvasStorageKey.baseCharacterSet) private var storedBaseCharacterSet = GlyphCanvasCharacterSetDefaults.baseString
    @AppStorage(GlyphCanvasStorageKey.stampSourceMode) private var storedStampSourceMode = StampSourceMode.characters.rawValue
    @ObservedObject var viewModel: AppViewModel

    private var stampSourceBinding: Binding<StampSourceMode> {
        Binding(
            get: { StampSourceMode(rawValue: storedStampSourceMode) ?? .characters },
            set: { storedStampSourceMode = $0.rawValue }
        )
    }

    private var stampMode: StampSourceMode {
        StampSourceMode(rawValue: storedStampSourceMode) ?? .characters
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Stamp source", selection: stampSourceBinding) {
                    Text("Characters").tag(StampSourceMode.characters)
                    Text("Words").tag(StampSourceMode.words)
                }
                .pickerStyle(.segmented)

                recentStampSetsSection

                if stampMode == .words {
                    Text("Paste or type text. Unique words (split on whitespace; punctuation trimmed from edges; contractions keep apostrophes) become stamps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $storedBaseCharacterSet)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 160)
                        .padding(8)
                        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                        )
                } else {
                    TextField("Character set", text: $storedBaseCharacterSet, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(4...12)
                        .font(.system(.body, design: .monospaced))
                    presetChips
                }

                HStack {
                    Text("Unique stamps: \(viewModel.activeStamps.count)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                if viewModel.showsCharacterSetFallbackNotice {
                    Text("Nothing to use from this input; falling back to default character set.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.body, design: .monospaced))
        .background(GalleryTheme.galleryScreenBackground.ignoresSafeArea())
        .navigationTitle("Stamps")
        .onAppear {
            syncViewModelFromStorage()
        }
        .onChange(of: storedBaseCharacterSet) { _, _ in
            syncViewModelFromStorage()
        }
        .onChange(of: storedStampSourceMode) { _, _ in
            syncViewModelFromStorage()
        }
    }

    private func syncViewModelFromStorage() {
        viewModel.baseCharacterSet = storedBaseCharacterSet
        viewModel.stampSourceMode = StampSourceMode(rawValue: storedStampSourceMode) ?? .characters
    }

    @ViewBuilder
    private var recentStampSetsSection: some View {
        if !viewModel.recentStampSets.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent stamp sets")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                FlowRecentStampSetChips(
                    items: viewModel.recentStampSets,
                    onTap: { recent in
                        storedStampSourceMode = recent.sourceMode.rawValue
                        storedBaseCharacterSet = recent.rawInput
                        syncViewModelFromStorage()
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var presetChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add preset")
                .font(.caption2)
                .foregroundStyle(.secondary)
            FlowStampPresetChips(
                items: [
                    ("A–Z", PredefinedStampSets.uppercaseLetters),
                    ("a–z", PredefinedStampSets.lowercaseLetters),
                    ("0–9", PredefinedStampSets.digits),
                    ("Punct", PredefinedStampSets.punctuation),
                    ("Emoji", PredefinedStampSets.emoji)
                ],
                onTap: { preset in
                    PredefinedStampSets.mergeAppendingUnique(into: &storedBaseCharacterSet, preset: preset)
                }
            )
        }
    }
}

// MARK: - Preset chips

private struct FlowStampPresetChips: View {
    let items: [(String, String)]
    let onTap: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, pair in
                Button(pair.0) {
                    onTap(pair.1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

private struct FlowRecentStampSetChips: View {
    let items: [RecentStampSet]
    let onTap: (RecentStampSet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items.prefix(6)) { item in
                Button {
                    onTap(item)
                } label: {
                    HStack(spacing: 8) {
                        Text(item.sourceMode == .words ? "words" : "chars")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Text(item.displayLabel.isEmpty ? item.rawInput : item.displayLabel)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(item.stampCount)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
