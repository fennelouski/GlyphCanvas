//
//  ProfileView.swift
//  GlyphCanvas
//
//  Mechanical Editor settings: preferences, encoding, system, legal, and local data.
//

import SwiftUI

struct ProfileView: View {
    @AppStorage(GlyphCanvasStorageKey.baseCharacterSet) private var storedBaseCharacterSet = GlyphCanvasCharacterSetDefaults.baseString
    @AppStorage(GlyphCanvasStorageKey.characterCaseMode) private var storedCharacterCaseMode = CharacterCaseMode.both.rawValue
    @AppStorage(GlyphCanvasStorageKey.highDetailMode) private var highDetailMode = true
    @AppStorage(GlyphCanvasStorageKey.autoArchive) private var autoArchive = false
    @AppStorage(GlyphCanvasStorageKey.showSourceOverlay) private var showSourceOverlay = false
    @AppStorage(GlyphCanvasStorageKey.optimizationMode) private var storedOptimizationMode = OptimizationMode.greedy.rawValue
    @AppStorage(GlyphCanvasStorageKey.debugOptimizationOverlay) private var debugOptimizationOverlay = false

    @EnvironmentObject private var library: ArtworkLibrary
    @Environment(\.openURL) private var openURL

    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.caption)
                    .foregroundStyle(Color.clear)
                    .frame(height: 1)
                    .accessibilityHeading(.h1)

                settingsHeader

                operatorCard

                SettingsSectionHeader(title: "PREFERENCES", dotColor: GalleryTheme.settingsAccent)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 12) {
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

                SettingsSectionHeader(title: "ENCODING", dotColor: GalleryTheme.settingsAccent)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 12) {
                    characterSetCard
                    caseFilterCard
                    SettingsToggleRow(
                        title: "Show Source Overlay",
                        subtitle: "When a source image is loaded, blends the original under the mosaic preview in Studio.",
                        isOn: $showSourceOverlay
                    )
                    optimizationModeCard
                    SettingsToggleRow(
                        title: "Optimization Debug",
                        subtitle: "Shows technical loss and region details while encoding (advanced).",
                        isOn: $debugOptimizationOverlay
                    )
                }

                SettingsSectionHeader(title: "SYSTEM INFO", dotColor: GalleryTheme.settingsAccent)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 12) {
                    buildVersionCard
                    softwareUpdateCard
                }

                SettingsSectionHeader(title: "CRITICAL ACTIONS", dotColor: GalleryTheme.settingsDanger)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 12) {
                    SettingsLinkRow(
                        icon: "shield.lefthalf.filled",
                        title: "Privacy Policy",
                        accessibilityHint: "Opens in Safari"
                    ) {
                        openBundledURL(infoPlistKey: "GlyphCanvasPrivacyPolicyURL", missingLabel: "Privacy Policy")
                    }
                    SettingsLinkRow(
                        icon: "doc.text",
                        title: "Terms of Service",
                        accessibilityHint: "Opens in Safari"
                    ) {
                        openBundledURL(infoPlistKey: "GlyphCanvasTermsURL", missingLabel: "Terms of Service")
                    }
                    deleteDataRow
                }

                footerText
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(GalleryTheme.settingsScreenBackground)
        #if os(macOS)
        .toolbar(.hidden, for: .windowToolbar)
        #else
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .confirmationDialog(
            "Delete all saved artworks and reset GlyphCanvas settings on this device?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All Data", role: .destructive) {
                performDeleteAllData()
            }
            Button("Cancel", role: .cancel) {}
        }
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

    private var settingsHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(GalleryTheme.settingsAccent)
                .accessibilityHidden(true)

            Text("MECHANICAL EDITOR")
                .font(.system(.subheadline, design: .monospaced).weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(GalleryTheme.settingsAccent)

            Spacer(minLength: 0)

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(GalleryTheme.bodyMuted)
                .accessibilityHidden(true)
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mechanical Editor")
    }

    private var operatorCard: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(GalleryTheme.settingsCardSurface)
                    .frame(width: 72, height: 72)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(GalleryTheme.bodyMuted)
                            .accessibilityHidden(true)
                    }

                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(GalleryTheme.settingsAccent, GalleryTheme.settingsCardSurface)
                    .offset(x: 4, y: 4)
                    .accessibilityHidden(true)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("JULIAN VANCE")
                    .font(.system(.body, design: .monospaced).weight(.bold))
                    .foregroundStyle(GalleryTheme.headline)

                Text("OPERATOR ID: #8829-MKIV")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(GalleryTheme.bodyMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                syncGalleryFromDisk()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("SYNC DATA")
                        .font(.system(.caption2, design: .monospaced).weight(.heavy))
                }
                .foregroundStyle(GalleryTheme.onAccentFill)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(GalleryTheme.settingsAccent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sync data")
            .accessibilityHint("Reloads the gallery list from files saved on this device")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(GalleryTheme.settingsCardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(GalleryTheme.studioStroke.opacity(0.5), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Operator Julian Vance, ID 8829 MK 4")
    }

    private var characterSetCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHARACTER SET")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(GalleryTheme.bodyMuted)

            TextField("Character set", text: $storedBaseCharacterSet, axis: .vertical)
                .lineLimit(3...8)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .padding(10)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .foregroundStyle(GalleryTheme.headline)
                .font(.system(.caption, design: .monospaced))
                .accessibilityLabel("Character set")
                .accessibilityHint("Characters used when generating the glyph mosaic")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(GalleryTheme.settingsCardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(GalleryTheme.studioStroke.opacity(0.5), lineWidth: 1)
        )
    }

    private var caseFilterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CASE FILTER")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(GalleryTheme.bodyMuted)

            Picker("Case filter", selection: caseModeSettingsBinding) {
                ForEach(CharacterCaseMode.allCases, id: \.self) { mode in
                    Image(systemName: mode.sfSymbolName)
                        .tag(mode)
                        .accessibilityLabel(mode.accessibilityLabel)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(GalleryTheme.settingsCardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(GalleryTheme.studioStroke.opacity(0.5), lineWidth: 1)
        )
    }

    private var optimizationModeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OPTIMIZATION MODE")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(GalleryTheme.bodyMuted)

            Picker("Optimization mode", selection: optimizationBinding) {
                Text("Greedy").tag(OptimizationMode.greedy)
                Text("Genetic").tag(OptimizationMode.genetic)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Optimization mode")
            .accessibilityHint("Greedy is faster per step; genetic searches more broadly in each region")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(GalleryTheme.settingsCardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(GalleryTheme.studioStroke.opacity(0.5), lineWidth: 1)
        )
    }

    private var buildVersionCard: some View {
        HStack(alignment: .center, spacing: 0) {
            Rectangle()
                .fill(GalleryTheme.settingsAccent)
                .frame(width: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("BUILD VERSION")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(GalleryTheme.bodyMuted)

                Text("v\(GalleryTheme.marketingVersion)-STABLE")
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(GalleryTheme.settingsAccent)
            }
            .padding(.leading, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(GalleryTheme.settingsCardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(GalleryTheme.studioStroke.opacity(0.5), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Build version v \(GalleryTheme.marketingVersion) stable")
    }

    private var softwareUpdateCard: some View {
        Button {
            openAppStoreForUpdates()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("SOFTWARE UPDATE")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(GalleryTheme.bodyMuted)

                HStack {
                    Text("CHECK FOR UPDATES")
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .foregroundStyle(GalleryTheme.headline)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GalleryTheme.headline)
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(GalleryTheme.settingsCardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(GalleryTheme.studioStroke.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Check for updates")
        .accessibilityHint("Opens the App Store")
    }

    private var deleteDataRow: some View {
        Button {
            showDeleteConfirmation = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(GalleryTheme.settingsDanger)
                    .accessibilityHidden(true)

                Text("DELETE ALL DATA")
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(GalleryTheme.settingsDanger)

                Spacer(minLength: 0)

                Text("IRREVERSIBLE")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(GalleryTheme.settingsDanger.opacity(0.85))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(GalleryTheme.settingsDanger.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(GalleryTheme.settingsDanger.opacity(0.55), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete all data")
        .accessibilityHint("Permanently removes saved artworks and resets app settings. Cannot be undone.")
    }

    private var footerText: some View {
        Text("MECHANICAL EDITOR INDUSTRIAL SUITE © 1994–2024")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(GalleryTheme.hudDetail)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
            .accessibilityLabel("Mechanical Editor Industrial Suite copyright 1994 through 2024")
    }

    private func syncGalleryFromDisk() {
        do {
            try library.reloadFromDisk()
            alertTitle = "Sync"
            alertMessage = "Gallery index reloaded from disk."
        } catch {
            alertTitle = "Sync failed"
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

// MARK: - Section header

private struct SettingsSectionHeader: View {
    let title: String
    let dotColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(.caption2, design: .monospaced).weight(.heavy))
                .tracking(1.0)
                .foregroundStyle(GalleryTheme.hudDetail)
        }
        .padding(.top, 4)
    }
}

// MARK: - Cards & rows

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var accessibilityHintOverride: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .foregroundStyle(GalleryTheme.headline)

                    Text(subtitle)
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(GalleryTheme.bodyMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(GalleryTheme.settingsAccent)
                    .accessibilityLabel(title)
                    .accessibilityHint(accessibilityHintOverride ?? subtitle)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(GalleryTheme.settingsCardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(GalleryTheme.studioStroke.opacity(0.5), lineWidth: 1)
        )
    }
}

private struct SettingsLinkRow: View {
    let icon: String
    let title: String
    var accessibilityHint: String = "Opens in Safari"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(GalleryTheme.headline.opacity(0.9))
                    .frame(width: 24, alignment: .center)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.system(.subheadline, design: .default).weight(.medium))
                    .foregroundStyle(GalleryTheme.headline)

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 16))
                    .foregroundStyle(GalleryTheme.bodyMuted)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(GalleryTheme.settingsCardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(GalleryTheme.studioStroke.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }
}

#Preview {
    NavigationStack {
        ProfileView()
            .environmentObject(ArtworkLibrary())
    }
}
