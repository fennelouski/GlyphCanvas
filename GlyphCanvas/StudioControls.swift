//
//  StudioControls.swift
//  GlyphCanvas
//

import SwiftUI

struct StudioParameterSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let leftLabel: String
    let rightLabel: String

    private var normalizedValue: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return max(0, min(1, (value - range.lowerBound) / span))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GalleryTheme.bodyMuted)
                Spacer()
                Text(String(format: "%.2f", normalizedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(GalleryTheme.studioAccent)
            }

            Slider(value: $value, in: range, step: step)
                .tint(GalleryTheme.studioAccent)

            HStack {
                Text(leftLabel)
                Spacer()
                Text(rightLabel)
            }
            .font(.caption2.monospaced())
            .foregroundStyle(GalleryTheme.hudDetail)
        }
    }
}

struct StudioSectionCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GalleryTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(GalleryTheme.studioStroke, lineWidth: 1)
            )
    }
}

struct DashedRoundedRectangle: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: 14, style: .continuous).path(in: rect)
    }
}
