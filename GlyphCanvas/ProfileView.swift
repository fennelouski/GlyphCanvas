//
//  ProfileView.swift
//  GlyphCanvas
//
//  Glyph Canvas settings: preferences, encoding, system, legal, and local data.
//

import SwiftUI

struct ProfileView: View {
    @AppStorage(GlyphCanvasStorageKey.baseCharacterSet) private var storedBaseCharacterSet = GlyphCanvasCharacterSetDefaults.baseString
    @AppStorage(GlyphCanvasStorageKey.stampSourceMode) private var storedStampSourceMode = StampSourceMode.characters.rawValue
    @AppStorage(GlyphCanvasStorageKey.characterCaseMode) private var storedCharacterCaseMode = CharacterCaseMode.both.rawValue
    @AppStorage(GlyphCanvasStorageKey.highDetailMode) private var highDetailMode = true
    @AppStorage(GlyphCanvasStorageKey.autoArchive) private var autoArchive = false
    @AppStorage(GlyphCanvasStorageKey.showSourceOverlay) private var showSourceOverlay = false
    @AppStorage(GlyphCanvasStorageKey.optimizationMode) private var storedOptimizationMode = OptimizationMode.greedy.rawValue
    @AppStorage(GlyphCanvasStorageKey.encodingComparisonMode) private var storedEncodingComparisonMode = EncodingComparisonMode.perceptual.rawValue
    @AppStorage(GlyphCanvasStorageKey.debugOptimizationOverlay) private var debugOptimizationOverlay = false
    @AppStorage(GlyphCanvasStorageKey.recentStampSets) private var storedRecentStampSets = "[]"

    @EnvironmentObject private var library: ArtworkLibrary
    @Environment(\.openURL) private var openURL

    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showDeleteConfirmation = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var presetMinimumWidth = 140.0
    @State private var selectedSection: SettingsSection = .preferences
    @State private var showsCompactDetail = false

    var body: some View {
        adaptiveLayout(compactDetail: false)
            .tint(settingsAccent)
            .navigationDestination(isPresented: $showsCompactDetail) {
                adaptiveLayout(compactDetail: true)
                    .tint(settingsAccent)
            }

    }

    private func adaptiveLayout(compactDetail: Bool) -> some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width >= (dynamicTypeSize.isAccessibilitySize ? 1040 : 760)
            Group {
                if isWide {
                    HStack(spacing: 0) {
                        sectionSidebar
                            .frame(width: dynamicTypeSize.isAccessibilitySize ? 460 : 240)
                        Divider()
                        sectionForm
                            .frame(maxWidth: 740)
                            .frame(maxWidth: .infinity)
                    }
                } else if compactDetail {
                    sectionForm
                } else {
                    sectionHub
                }
            }
            .background(settingsBackground)
            .navigationTitle(compactDetail && !isWide ? selectedSection.title : "Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onChange(of: isWide) { oldValue, newValue in
                if !compactDetail && oldValue && !newValue {
                    showsCompactDetail = true
                }
            }
        }
            .alert(alertTitle, isPresented: visiblePresentation($showAlert, compactDetail: compactDetail)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .confirmationDialog(
                "Delete all saved artworks and reset GlyphCanvas settings on this device?",
                isPresented: visiblePresentation($showDeleteConfirmation, compactDetail: compactDetail),
                titleVisibility: .visible
            ) {
                Button("Delete All Data", role: .destructive) {
                    performDeleteAllData()
                }
                Button("Cancel", role: .cancel) {}
            }
    }

    private func visiblePresentation(_ isPresented: Binding<Bool>, compactDetail: Bool) -> Binding<Bool> {
        Binding(
            get: { compactDetail == showsCompactDetail && isPresented.wrappedValue },
            set: { value in
                if compactDetail == showsCompactDetail { isPresented.wrappedValue = value }
            }
        )
    }

    private var settingsAccent: Color {
        colorScheme == .dark ? GalleryTheme.settingsAccent : Color(red: 0.15, green: 0.38, blue: 0.67)
    }

    private var settingsBackground: some View {
        LinearGradient(
            colors: [settingsAccent.opacity(0.09), GalleryTheme.settingsScreenBackground],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .background(GalleryTheme.settingsScreenBackground)
    }

    private var sectionSidebar: some View {
        List(selection: Binding<SettingsSection?>(
            get: { selectedSection },
            set: { if let section = $0 { selectedSection = section } }
        )) {
            settingsHeader
                .listRowBackground(Color.clear)
            ForEach(SettingsSection.allCases) { section in
                sectionLabel(section, isSelected: selectedSection == section)
                    .tag(section)
                    .accessibilityIdentifier("settings.section.\(section.rawValue)")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private var sectionHub: some View {
        List {
            Section {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        selectedSection = section
                        showsCompactDetail = true
                    } label: {
                        HStack {
                            sectionLabel(section)
                            Spacer(minLength: 12)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.section.\(section.rawValue)")
                }
            } header: {
                settingsHeader
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func sectionLabel(_ section: SettingsSection, isSelected: Bool = false) -> some View {
        let selectedForeground = colorScheme == .dark ? GalleryTheme.onAccentFill : Color.white
        return
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .font(.headline)
                    .foregroundStyle(isSelected ? selectedForeground : GalleryTheme.headline)
                Text(section.subtitle)
                    .font(.caption)
                    .foregroundStyle(isSelected ? selectedForeground : GalleryTheme.bodyMuted)
            }
            .padding(.vertical, 6)
        } icon: {
            Image(systemName: section.symbol)
                .foregroundStyle(isSelected ? selectedForeground : (section == .critical ? GalleryTheme.settingsDanger : settingsAccent))
                .fixedSize()
                .accessibilityHidden(true)
        }
    }

    private var sectionForm: some View {
        Form {
            switch selectedSection {
            case .preferences:
                Section("Mosaics") {
                    SettingsToggleRow(
                        title: "High Detail Mode",
                        subtitle: "Increases character density in mosaics. Consumes more processing power.",
                        isOn: $highDetailMode
                    )
                    SettingsToggleRow(
                        title: "Auto-Archive",
                        subtitle: "When enabled, successfully exported PNGs are also saved to the on-device gallery.",
                        isOn: $autoArchive
                    )
                }
                Section("On this device") {
                    Button("Reload gallery", systemImage: "arrow.triangle.2.circlepath") {
                        syncGalleryFromDisk()
                    }
                    .accessibilityHint("Reloads the gallery list from files saved on this device")
                }
            case .encoding:
                Section("Active stamps") {
                    stampPreview
                    characterSetCard
                    caseFilterCard
                }
                Section("Encoding") {
                    optimizationModeCard
                    encodingComparisonModeCard
                    SettingsToggleRow(
                        title: "Show Source Overlay",
                        subtitle: "When a source image is loaded, blends the original under the mosaic preview in Studio.",
                        isOn: $showSourceOverlay
                    )
                    SettingsToggleRow(
                        title: "Optimization Debug",
                        subtitle: "Shows technical loss and region details while encoding (advanced).",
                        isOn: $debugOptimizationOverlay
                    )
                }
            case .system:
                Section("System info") {
                    buildVersionCard
                    softwareUpdateCard
                }
            case .critical:
                Section("Legal") {
                    SettingsLinkRow(icon: "shield.lefthalf.filled", title: "Privacy Policy") {
                        openBundledURL(infoPlistKey: "GlyphCanvasPrivacyPolicyURL", missingLabel: "Privacy Policy")
                    }
                    SettingsLinkRow(icon: "doc.text", title: "Terms of Service") {
                        openBundledURL(infoPlistKey: "GlyphCanvasTermsURL", missingLabel: "Terms of Service")
                    }
                }
                Section {
                    deleteDataRow
                } header: {
                    Text("Local data")
                } footer: {
                    Text("Permanently removes saved artworks and resets app settings on this device. This cannot be undone.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("settings.detail.\(selectedSection.rawValue)")
    }

    private var stampPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(profileActiveStamps.prefix(16).joined(separator: "   "))
                .font(.system(.title2, design: .monospaced).weight(.medium))
                .foregroundStyle(settingsAccent)
                .lineLimit(4)
                .accessibilityLabel("Stamp preview")
                .accessibilityValue(profileActiveStamps.prefix(16).joined(separator: ", "))
            Text("\(profileActiveStampCount) unique stamps")
                .font(.caption.monospacedDigit())
                .foregroundStyle(GalleryTheme.bodyMuted)
        }
        .padding(.vertical, 8)
    }

    private var caseModeSettingsBinding: Binding<CharacterCaseMode> {
        Binding(
            get: { CharacterCaseMode(rawValue: storedCharacterCaseMode) ?? .both },
            set: { storedCharacterCaseMode = $0.rawValue }
        )
    }

    private var optimizationBinding: Binding<OptimizationMode> {
        Binding(
            get: { OptimizationMode(rawValue: storedOptimizationMode) ?? .greedy },
            set: { storedOptimizationMode = $0.rawValue }
        )
    }

    private var encodingComparisonBinding: Binding<EncodingComparisonMode> {
        Binding(
            get: { EncodingComparisonMode(rawValue: storedEncodingComparisonMode) ?? .perceptual },
            set: { storedEncodingComparisonMode = $0.rawValue }
        )
    }

    private var stampSourceSettingsBinding: Binding<StampSourceMode> {
        Binding(
            get: { StampSourceMode(rawValue: storedStampSourceMode) ?? .characters },
            set: { storedStampSourceMode = $0.rawValue }
        )
    }

    private var profileStampMode: StampSourceMode {
        StampSourceMode(rawValue: storedStampSourceMode) ?? .characters
    }

    private var profileActiveStamps: [String] {
        StampSetPipeline.activeSet(
            base: storedBaseCharacterSet,
            mode: CharacterCaseMode(rawValue: storedCharacterCaseMode) ?? .both,
            source: profileStampMode
        )
    }

    private var profileActiveStampCount: Int { profileActiveStamps.count }

    private var profileShowsStampFallback: Bool {
        StampSetPipeline.isEffectivelyEmpty(
            base: storedBaseCharacterSet,
            mode: CharacterCaseMode(rawValue: storedCharacterCaseMode) ?? .both,
            source: profileStampMode
        )
    }

    private var profileRecentStampSets: [RecentStampSet] {
        RecentStampSetStore.decode(from: storedRecentStampSets)
    }

    private var settingsHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(settingsAccent)
                .accessibilityHidden(true)

            Text("GLYPH CANVAS")
                .font(.system(.subheadline, design: .monospaced).weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(settingsAccent)

            Spacer(minLength: 0)

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(GalleryTheme.bodyMuted)
                .accessibilityHidden(true)
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Glyph Canvas")
    }

    private var characterSetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Stamp source", selection: stampSourceSettingsBinding) {
                Text("Characters").tag(StampSourceMode.characters)
                Text("Words").tag(StampSourceMode.words)
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Stamp source")

            if profileStampMode == .words {
                Text("Paste text; unique words become stamps. Whitespace splits tokens; edge punctuation is removed; apostrophes inside words are kept.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(GalleryTheme.bodyMuted)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $storedBaseCharacterSet)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(GalleryTheme.headline)
                    .accessibilityLabel("Word source text")
            } else {
                TextField("Character set", text: $storedBaseCharacterSet, axis: .vertical)
                    .lineLimit(3...8)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .foregroundStyle(GalleryTheme.headline)
                    .font(.system(.caption, design: .monospaced))
                    .accessibilityLabel("Character set")
                    .accessibilityHint("Characters used when generating the glyph mosaic")

                stampPresetButtons
            }

            if !profileRecentStampSets.isEmpty {
                recentStampSetButtons
            }

            if profileShowsStampFallback {
                Text("Nothing usable in this input; default character set is used.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(GalleryTheme.bodyMuted)
            }
        }
    }

    private var stampPresetButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add preset")
                .font(.caption)
                .foregroundStyle(GalleryTheme.bodyMuted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: presetMinimumWidth), alignment: .leading)], alignment: .leading, spacing: 8) {
                stampPresetButton("A–Z", PredefinedStampSets.uppercaseLetters)
                stampPresetButton("a–z", PredefinedStampSets.lowercaseLetters)
                stampPresetButton("0–9", PredefinedStampSets.digits)
                stampPresetButton("Punctuation", PredefinedStampSets.punctuation)
                stampPresetButton("Emoji", PredefinedStampSets.emoji)
            }
        }
    }

    private var recentStampSetButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECENT STAMP SETS")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(GalleryTheme.bodyMuted)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(profileRecentStampSets.prefix(6)) { recent in
                    Button {
                        storedStampSourceMode = recent.sourceMode.rawValue
                        storedBaseCharacterSet = recent.rawInput
                    } label: {
                        HStack(spacing: 8) {
                            Text(recent.sourceMode == .words ? "words" : "chars")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(GalleryTheme.bodyMuted)
                            Text(recent.displayLabel.isEmpty ? recent.rawInput : recent.displayLabel)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(2)
                                .foregroundStyle(GalleryTheme.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(recent.stampCount)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(GalleryTheme.bodyMuted)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                    .tint(settingsAccent)
                }
            }
        }
    }

    private func stampPresetButton(_ title: String, _ preset: String) -> some View {
        Button(title) {
            PredefinedStampSets.mergeAppendingUnique(into: &storedBaseCharacterSet, preset: preset)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(settingsAccent)
    }

    private var caseFilterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Case filter", selection: caseModeSettingsBinding) {
                ForEach(CharacterCaseMode.allCases, id: \.self) { mode in
                    Text(mode.accessibilityLabel)
                        .tag(mode)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var optimizationModeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Optimization mode", selection: optimizationBinding) {
                Text("Greedy").tag(OptimizationMode.greedy)
                Text("Genetic").tag(OptimizationMode.genetic)
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Optimization mode")
            .accessibilityHint("Greedy is faster per step; genetic searches more broadly in each region")
        }
    }

    private var encodingComparisonModeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Encoding comparison", selection: encodingComparisonBinding) {
                Text("Match").tag(EncodingComparisonMode.perceptual)
                Text("Edges").tag(EncodingComparisonMode.edges)
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Encoding comparison")
            .accessibilityHint("Match follows color like the source; Edges prefers stamp ink along strong edges")

            Text("Edges mode places ink along outlines instead of matching interior color.")
                .font(.caption2)
                .foregroundStyle(GalleryTheme.bodyMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var buildVersionCard: some View {
        LabeledContent("Build version") {
            Text("v\(GalleryTheme.marketingVersion)-STABLE")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(settingsAccent)
        }
    }

    private var softwareUpdateCard: some View {
        Button("Check for updates", systemImage: "arrow.up.right.square") {
            openAppStoreForUpdates()
        }
        .accessibilityHint("Opens the App Store")
    }

    private var deleteDataRow: some View {
        Button("Delete all data", systemImage: "trash", role: .destructive) {
            showDeleteConfirmation = true
        }
        .accessibilityHint("Permanently removes saved artworks and resets app settings. Cannot be undone.")
    }

    private func syncGalleryFromDisk() {
        do {
            try library.reloadFromDisk()
            alertTitle = "Gallery reloaded"
            alertMessage = "Gallery index reloaded from disk."
        } catch {
            alertTitle = "Reload failed"
            alertMessage = error.localizedDescription
        }
        showAlert = true
    }

    private func openAppStoreForUpdates() {
        let id = (Bundle.main.object(forInfoDictionaryKey: "GlyphCanvasAppStoreID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !id.isEmpty, let url = URL(string: "https://apps.apple.com/app/id\(id)") {
            openURL(url)
            return
        }
        if let url = URL(string: "https://apps.apple.com/search?term=GlyphCanvas") {
            openURL(url)
        }
    }

    private func openBundledURL(infoPlistKey: String, missingLabel: String) {
        let raw = (Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty, let url = URL(string: raw) else {
            alertTitle = "\(missingLabel) unavailable"
            alertMessage = "Add \(infoPlistKey) to Info.plist with a valid URL."
            showAlert = true
            return
        }
        openURL(url)
    }

    private func performDeleteAllData() {
        do {
            try library.deleteAllArtworks()
            GlyphCanvasStorageKey.clearAllGlyphCanvasKeys()
            storedBaseCharacterSet = GlyphCanvasCharacterSetDefaults.baseString
            storedCharacterCaseMode = CharacterCaseMode.both.rawValue
            highDetailMode = true
            autoArchive = false
            showSourceOverlay = false
            storedOptimizationMode = OptimizationMode.greedy.rawValue
            storedEncodingComparisonMode = EncodingComparisonMode.perceptual.rawValue
            debugOptimizationOverlay = false
            alertTitle = "Data removed"
            alertMessage = "Local gallery and GlyphCanvas settings were cleared."
        } catch {
            alertTitle = "Delete failed"
            alertMessage = error.localizedDescription
        }
        showAlert = true
    }
}

// MARK: - Focused settings sections

private enum SettingsSection: String, CaseIterable, Identifiable {
    case preferences, encoding, system, critical
    var id: Self { self }
    var title: String {
        switch self {
        case .preferences: "Preferences"
        case .encoding: "Encoding"
        case .system: "System"
        case .critical: "Critical actions"
        }
    }
    var subtitle: String {
        switch self {
        case .preferences: "Detail, archive & gallery"
        case .encoding: "Stamps, case & optimization"
        case .system: "Version & updates"
        case .critical: "Legal & local data"
        }
    }
    var symbol: String {
        switch self {
        case .preferences: "slider.horizontal.3"
        case .encoding: "textformat"
        case .system: "info.circle"
        case .critical: "exclamationmark.shield"
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(GalleryTheme.bodyMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

private struct SettingsLinkRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: icon, action: action)
            .accessibilityHint("Opens in Safari")
    }
}

#Preview {
    NavigationStack {
        ProfileView()
            .environmentObject(ArtworkLibrary())
    }
}
