//
//  StudioControls.swift
//  GlyphCanvas
//

import SwiftUI

struct StudioParameterSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let leftLabel: LocalizedStringKey
    let rightLabel: LocalizedStringKey
    var format: String = "%.0f"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(GalleryTheme.headline)
                Spacer()
                Text(String(format: format, value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(GalleryTheme.bodyMuted)
                    .contentTransition(.numericText())
            }

            Slider(value: $value, in: range, step: step)
                .accessibilityLabel(Text(title))
                .accessibilityValue(String(format: format, value))

            HStack {
                Text(leftLabel)
                Spacer()
                Text(rightLabel)
            }
            .font(.caption2)
            .foregroundStyle(GalleryTheme.hudDetail)
            .accessibilityHidden(true)
        }
    }
}

struct StudioSectionCard<Content: View>: View {
    @Environment(\.appTheme) private var theme
    var title: LocalizedStringKey? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(GalleryTheme.bodyMuted)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
