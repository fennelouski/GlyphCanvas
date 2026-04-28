//
//  ImportImageAdjustView.swift
//  GlyphCanvas
//

import CoreGraphics
import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Rotate and crop before the image is sent to the studio engine. Chrome is icon-first; confirm uses the word "Next".
struct ImportImageAdjustView: View {
    let image: CGImage
    var onCancel: () -> Void
    var onComplete: (CGImage) -> Void

    @State private var workingImage: CGImage
    /// Normalized crop in top-left coordinates (0…1), matching SwiftUI layout.
    @State private var cropNorm = CGRect(x: 0, y: 0, width: 1, height: 1)

    init(image: CGImage, onCancel: @escaping () -> Void, onComplete: @escaping (CGImage) -> Void) {
        self.image = image
        self.onCancel = onCancel
        self.onComplete = onComplete
        _workingImage = State(initialValue: image)
    }

    private var minNormWidth: CGFloat {
        max(2.0 / CGFloat(workingImage.width), 32.0 / CGFloat(workingImage.width))
    }

    private var minNormHeight: CGFloat {
        max(2.0 / CGFloat(workingImage.height), 32.0 / CGFloat(workingImage.height))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                cropStage
                bottomBar
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var cropStage: some View {
        GeometryReader { geo in
            let container = geo.size
            let imageSize = CGSize(width: workingImage.width, height: workingImage.height)
            let fitted = Self.aspectFit(container: container, imageSize: imageSize)
            let cropFrame = CGRect(
                x: fitted.minX + cropNorm.origin.x * fitted.width,
                y: fitted.minY + cropNorm.origin.y * fitted.height,
                width: cropNorm.width * fitted.width,
                height: cropNorm.height * fitted.height
            )

            ZStack(alignment: .topLeading) {
                imageLayer(fitted: fitted)
                dimmingLayer(fitted: fitted, cropFrame: cropFrame)
                cropBorder(cropFrame: cropFrame)
                ForEach(CropHandle.allCases, id: \.self) { handle in
                    handleKnob(
                        handle: handle,
                        cropFrame: cropFrame,
                        fitted: fitted
                    )
                }
            }
            .frame(width: container.width, height: container.height)
            .coordinateSpace(name: "importAdjustStage")
        }
        .padding(.horizontal, 12)
    }

    private func imageLayer(fitted: CGRect) -> some View {
        #if os(macOS)
        Image(nsImage: NSImage(cgImage: workingImage, size: NSSize(width: workingImage.width, height: workingImage.height)))
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .frame(width: fitted.width, height: fitted.height)
            .position(x: fitted.midX, y: fitted.midY)
        #else
        Image(decorative: workingImage, scale: 1.0)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .frame(width: fitted.width, height: fitted.height)
            .position(x: fitted.midX, y: fitted.midY)
        #endif
    }

    private func dimmingLayer(fitted: CGRect, cropFrame: CGRect) -> some View {
        let dim = Color.black.opacity(0.52)
        return ZStack(alignment: .topLeading) {
            if cropFrame.minY > fitted.minY + 0.5 {
                dim.frame(width: fitted.width, height: cropFrame.minY - fitted.minY)
                    .offset(x: fitted.minX, y: fitted.minY)
            }
            if cropFrame.maxY < fitted.maxY - 0.5 {
                dim.frame(width: fitted.width, height: fitted.maxY - cropFrame.maxY)
                    .offset(x: fitted.minX, y: cropFrame.maxY)
            }
            if cropFrame.minX > fitted.minX + 0.5 {
                dim.frame(width: cropFrame.minX - fitted.minX, height: cropFrame.height)
                    .offset(x: fitted.minX, y: cropFrame.minY)
            }
            if cropFrame.maxX < fitted.maxX - 0.5 {
                dim.frame(width: fitted.maxX - cropFrame.maxX, height: cropFrame.height)
                    .offset(x: cropFrame.maxX, y: cropFrame.minY)
            }
        }
        .allowsHitTesting(false)
    }

    private func cropBorder(cropFrame: CGRect) -> some View {
        Rectangle()
            .strokeBorder(Color.white, lineWidth: 2)
            .frame(width: max(1, cropFrame.width), height: max(1, cropFrame.height))
            .position(x: cropFrame.midX, y: cropFrame.midY)
            .allowsHitTesting(false)
    }

    private func handleKnob(handle: CropHandle, cropFrame: CGRect, fitted: CGRect) -> some View {
        let center = handle.center(in: cropFrame)
        let knobSize: CGFloat = 28
        return Circle()
            .fill(Color.white.opacity(0.95))
            .frame(width: knobSize, height: knobSize)
            .overlay {
                Circle()
                    .strokeBorder(Color.black.opacity(0.25), lineWidth: 1)
            }
            .position(center)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("importAdjustStage"))
                    .onChanged { value in
                        applyDrag(handle: handle, finger: value.location, fitted: fitted)
                    }
            )
            .accessibilityLabel(handle.accessibilityLabel)
    }

    private func applyDrag(handle: CropHandle, finger: CGPoint, fitted: CGRect) {
        let n = normalizedPoint(finger, fitted: fitted)
        let r = cropNorm
        let minW = minNormWidth
        let minH = minNormHeight
        let minX = r.minX
        let minY = r.minY
        let maxX = r.maxX
        let maxY = r.maxY

        var next = r
        switch handle {
        case .topLeft:
            let fixedRight = maxX
            let fixedBottom = maxY
            let nx = min(n.x, fixedRight - minW)
            let ny = min(n.y, fixedBottom - minH)
            next.origin.x = max(0, nx)
            next.origin.y = max(0, ny)
            next.size.width = fixedRight - next.origin.x
            next.size.height = fixedBottom - next.origin.y
        case .topRight:
            let fixedLeft = minX
            let fixedBottom = maxY
            let nMaxX = max(n.x, fixedLeft + minW)
            let ny = min(n.y, fixedBottom - minH)
            next.origin.x = fixedLeft
            next.origin.y = max(0, ny)
            next.size.width = min(1, nMaxX) - fixedLeft
            next.size.height = fixedBottom - next.origin.y
        case .bottomLeft:
            let fixedRight = maxX
            let fixedTop = minY
            let nx = min(n.x, fixedRight - minW)
            let nMaxY = max(n.y, fixedTop + minH)
            next.origin.x = max(0, nx)
            next.origin.y = fixedTop
            next.size.width = fixedRight - next.origin.x
            next.size.height = min(1, nMaxY) - fixedTop
        case .bottomRight:
            let fixedLeft = minX
            let fixedTop = minY
            let nMaxX = max(n.x, fixedLeft + minW)
            let nMaxY = max(n.y, fixedTop + minH)
            next.origin.x = fixedLeft
            next.origin.y = fixedTop
            next.size.width = min(1, nMaxX) - fixedLeft
            next.size.height = min(1, nMaxY) - fixedTop
        }
        cropNorm = clampCrop(next)
    }

    private func clampCrop(_ r: CGRect) -> CGRect {
        var out = r
        let minW = minNormWidth
        let minH = minNormHeight
        out.origin.x = max(0, min(out.origin.x, 1 - minW))
        out.origin.y = max(0, min(out.origin.y, 1 - minH))
        out.size.width = max(minW, min(out.size.width, 1 - out.origin.x))
        out.size.height = max(minH, min(out.size.height, 1 - out.origin.y))
        return out
    }

    private func normalizedPoint(_ point: CGPoint, fitted: CGRect) -> CGPoint {
        CGPoint(
            x: (point.x - fitted.minX) / max(fitted.width, 1),
            y: (point.y - fitted.minY) / max(fitted.height, 1)
        )
    }

    private var bottomBar: some View {
        HStack(spacing: 24) {
            Button {
                rotate(ccw: true)
            } label: {
                Image(systemName: "rotate.left")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rotate counterclockwise")

            Button {
                rotate(ccw: false)
            } label: {
                Image(systemName: "rotate.right")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rotate clockwise")

            Spacer(minLength: 12)

            Button {
                commit()
            } label: {
                Text("Next")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    private func rotate(ccw: Bool) {
        let turns = ccw ? 1 : -1
        guard let rotated = ImageProcessing.cgImageRotatedQuarterTurns(workingImage, quarterTurns: turns) else { return }
        workingImage = rotated
        cropNorm = CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    private func commit() {
        guard let cropped = ImageProcessing.cgImageCroppingNormalizedTopLeft(workingImage, normalizedRect: cropNorm) else {
            return
        }
        onComplete(cropped)
    }

    private enum CropHandle: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight

        func center(in cropFrame: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: cropFrame.minX, y: cropFrame.minY)
            case .topRight: return CGPoint(x: cropFrame.maxX, y: cropFrame.minY)
            case .bottomLeft: return CGPoint(x: cropFrame.minX, y: cropFrame.maxY)
            case .bottomRight: return CGPoint(x: cropFrame.maxX, y: cropFrame.maxY)
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .topLeft: return "Crop top left"
            case .topRight: return "Crop top right"
            case .bottomLeft: return "Crop bottom left"
            case .bottomRight: return "Crop bottom right"
            }
        }
    }

    private static func aspectFit(container: CGSize, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return .zero
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        let x = (container.width - w) / 2
        let y = (container.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
