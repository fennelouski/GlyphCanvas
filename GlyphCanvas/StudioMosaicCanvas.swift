//
//  StudioMosaicCanvas.swift
//  GlyphCanvas
//

import CoreGraphics
import SwiftUI

// MARK: - Mosaic layers (no gestures)

struct StudioMosaicLayers: View {
    let displayImage: CGImage
    var sourceOverlay: CGImage?
    var showSourceOverlay: Bool
    var imagePadding: CGFloat = 10

    var body: some View {
        ZStack {
            Image(decorative: displayImage, scale: 1.0)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .padding(imagePadding)
            if showSourceOverlay, let source = sourceOverlay {
                Image(decorative: source, scale: 1.0)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(imagePadding)
                    .opacity(0.22)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Interactive canvas (view-only zoom; does not affect CGImage)

struct StudioMosaicInteractiveCanvas: View {
    let displayImage: CGImage
    var sourceOverlay: CGImage?
    var showSourceOverlay: Bool
    var imagePadding: CGFloat = 10

    /// When set, single-tap opens fullscreen (embedded mode only).
    var onRequestFullscreen: (() -> Void)?
    var scrollDisabledBinding: Binding<Bool>?

    private static let doubleTapScale: CGFloat = 2.0
    private static let minScale: CGFloat = 1.0
    private static let maxScale: CGFloat = 4.0

    @State private var pinchBaseScale: CGFloat = 1.0
    @State private var pinchGestureMagnification: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero

    @State private var containerSize: CGSize = .zero
    @State private var fittedContentSize: CGSize = .zero

    private var liveScale: CGFloat {
        min(Self.maxScale, max(Self.minScale, pinchBaseScale * pinchGestureMagnification))
    }

    var body: some View {
        GeometryReader { geo in
            let fitted = fittedContentSize(in: geo.size, image: displayImage, padding: imagePadding)
            ZStack {
                StudioMosaicLayers(
                    displayImage: displayImage,
                    sourceOverlay: sourceOverlay,
                    showSourceOverlay: showSourceOverlay,
                    imagePadding: imagePadding
                )
                .scaleEffect(liveScale, anchor: .center)
                .offset(dragOffset)
                .frame(width: fitted.width, height: fitted.height)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onAppear {
                containerSize = geo.size
                fittedContentSize = fitted
            }
            .onChange(of: geo.size) { _, new in
                containerSize = new
                fittedContentSize = fittedContentSize(in: new, image: displayImage, padding: imagePadding)
                dragOffset = clampOffset(
                    dragOffset,
                    scale: liveScale,
                    container: new,
                    content: fittedContentSize
                )
                dragStartOffset = dragOffset
            }
            .modifier(CanvasTapGesturesModifier(
                onRequestFullscreen: onRequestFullscreen,
                onDoubleTap: {
                    toggleDoubleTapZoom()
                }
            ))
            .simultaneousGesture(magnificationGesture)
            .simultaneousGesture(dragGesture(container: geo.size, fitted: fitted))
            .onChange(of: liveScale) { _, newValue in
                scrollDisabledBinding?.wrappedValue = newValue > 1.02
            }
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { pinchGestureMagnification = $0 }
            .onEnded { _ in
                pinchBaseScale = min(Self.maxScale, max(Self.minScale, pinchBaseScale * pinchGestureMagnification))
                pinchGestureMagnification = 1.0
                if pinchBaseScale <= 1.02 {
                    pinchBaseScale = 1.0
                    dragOffset = .zero
                    dragStartOffset = .zero
                } else {
                    dragOffset = clampOffset(
                        dragOffset,
                        scale: pinchBaseScale,
                        container: containerSize,
                        content: fittedContentSize
                    )
                    dragStartOffset = dragOffset
                }
            }
    }

    private func dragGesture(container: CGSize, fitted: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard liveScale > 1.02 else { return }
                let next = CGSize(
                    width: dragStartOffset.width + value.translation.width,
                    height: dragStartOffset.height + value.translation.height
                )
                dragOffset = clampOffset(next, scale: liveScale, container: container, content: fitted)
            }
            .onEnded { _ in
                dragStartOffset = dragOffset
            }
    }

    private func toggleDoubleTapZoom() {
        if liveScale > 1.25 {
            withAnimation(.easeInOut(duration: 0.2)) {
                pinchBaseScale = 1.0
                pinchGestureMagnification = 1.0
                dragOffset = .zero
                dragStartOffset = .zero
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                pinchBaseScale = Self.doubleTapScale
                pinchGestureMagnification = 1.0
                dragOffset = .zero
                dragStartOffset = .zero
            }
        }
    }

    private func fittedContentSize(in container: CGSize, image: CGImage, padding: CGFloat) -> CGSize {
        let w = max(1, container.width - padding * 2)
        let h = max(1, container.height - padding * 2)
        let iw = CGFloat(image.width)
        let ih = CGFloat(image.height)
        let scale = min(w / iw, h / ih)
        return CGSize(width: iw * scale, height: ih * scale)
    }

    private func clampOffset(
        _ offset: CGSize,
        scale: CGFloat,
        container: CGSize,
        content: CGSize
    ) -> CGSize {
        let scaledW = content.width * scale
        let scaledH = content.height * scale
        let maxX = max(0, (scaledW - container.width) / 2)
        let maxY = max(0, (scaledH - container.height) / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }
}

/// Applies double-tap before single-tap so single-tap waits for double-tap to fail (UIKit semantics on Apple platforms).
private struct CanvasTapGesturesModifier: ViewModifier {
    let onRequestFullscreen: (() -> Void)?
    let onDoubleTap: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if let onFullscreen = onRequestFullscreen {
            content
                .onTapGesture(count: 2, perform: onDoubleTap)
                .onTapGesture(count: 1, perform: onFullscreen)
        } else {
            content
                .onTapGesture(count: 2, perform: onDoubleTap)
        }
    }
}

// MARK: - Fullscreen shell

struct StudioMosaicFullscreenShell: View {
    let displayImage: CGImage
    var sourceOverlay: CGImage?
    var showSourceOverlay: Bool
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            StudioMosaicInteractiveCanvas(
                displayImage: displayImage,
                sourceOverlay: sourceOverlay,
                showSourceOverlay: showSourceOverlay,
                imagePadding: 10,
                onRequestFullscreen: nil,
                scrollDisabledBinding: nil
            )
            .background(Color.black.opacity(0.92))
            .navigationTitle("Canvas")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}
