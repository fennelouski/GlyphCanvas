//
//  GalleryTilePressOverlay.swift
//  GlyphCanvas
//
//  UILongPressGestureRecognizer / NSPressGestureRecognizer with minimum duration 0 and
//  allowable movement so scrolling in a parent ScrollView can win; simultaneous
//  recognition with the scroll pan avoids stealing the whole gesture stream.
//

import SwiftUI

#if os(iOS) || os(visionOS)
import UIKit

struct GalleryTilePressOverlay: UIViewRepresentable {
    var onPressBegan: () -> Void
    /// `liftedNormally` is true only for touch end (.ended), not scroll cancellation (.cancelled / .failed).
    var onPressReleased: (_ duration: TimeInterval, _ liftedNormally: Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPressBegan: onPressBegan, onPressReleased: onPressReleased)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePress(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = 24
        press.cancelsTouchesInView = false
        press.delegate = context.coordinator

        view.addGestureRecognizer(press)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onPressBegan = onPressBegan
        context.coordinator.onPressReleased = onPressReleased
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onPressBegan: () -> Void
        var onPressReleased: (_ duration: TimeInterval, _ liftedNormally: Bool) -> Void
        private var beganAt: Date?

        init(
            onPressBegan: @escaping () -> Void,
            onPressReleased: @escaping (_ duration: TimeInterval, _ liftedNormally: Bool) -> Void
        ) {
            self.onPressBegan = onPressBegan
            self.onPressReleased = onPressReleased
        }

        @objc func handlePress(_ gr: UILongPressGestureRecognizer) {
            switch gr.state {
            case .began:
                beganAt = Date()
                onPressBegan()
            case .ended:
                let duration = beganAt.map { Date().timeIntervalSince($0) } ?? 0
                onPressReleased(duration, true)
                beganAt = nil
            case .cancelled, .failed:
                let duration = beganAt.map { Date().timeIntervalSince($0) } ?? 0
                onPressReleased(duration, false)
                beganAt = nil
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

#elseif os(macOS)
import AppKit

struct GalleryTilePressOverlay: NSViewRepresentable {
    var onPressBegan: () -> Void
    var onPressReleased: (_ duration: TimeInterval, _ liftedNormally: Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPressBegan: onPressBegan, onPressReleased: onPressReleased)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        if let layer = view.layer {
            layer.backgroundColor = NSColor.clear.cgColor
        }

        let press = NSPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePress(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = 24
        press.delegate = context.coordinator

        view.addGestureRecognizer(press)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onPressBegan = onPressBegan
        context.coordinator.onPressReleased = onPressReleased
    }

    final class Coordinator: NSObject, NSGestureRecognizerDelegate {
        var onPressBegan: () -> Void
        var onPressReleased: (_ duration: TimeInterval, _ liftedNormally: Bool) -> Void
        private var beganAt: Date?

        init(
            onPressBegan: @escaping () -> Void,
            onPressReleased: @escaping (_ duration: TimeInterval, _ liftedNormally: Bool) -> Void
        ) {
            self.onPressBegan = onPressBegan
            self.onPressReleased = onPressReleased
        }

        @objc func handlePress(_ gr: NSPressGestureRecognizer) {
            switch gr.state {
            case .began:
                beganAt = Date()
                onPressBegan()
            case .ended:
                let duration = beganAt.map { Date().timeIntervalSince($0) } ?? 0
                onPressReleased(duration, true)
                beganAt = nil
            case .cancelled, .failed:
                let duration = beganAt.map { Date().timeIntervalSince($0) } ?? 0
                onPressReleased(duration, false)
                beganAt = nil
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: NSGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

#endif
