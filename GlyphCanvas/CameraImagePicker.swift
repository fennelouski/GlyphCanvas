//
//  CameraImagePicker.swift
//  GlyphCanvas
//

#if os(iOS) && !os(visionOS)
import CoreGraphics
import SwiftUI
import UIKit

/// `UIImage.cgImage` ignores `imageOrientation`; camera photos are often stored in sensor orientation.
/// Drawing the image applies orientation so the resulting bitmap matches what the user saw in the preview.
private extension UIImage {
    func cgImageApplyingDisplayOrientation() -> CGImage? {
        guard imageOrientation != .up else { return cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let drawn = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: self.size))
        }
        return drawn.cgImage
    }
}

struct CameraImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    let onComplete: (CGImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss, onComplete: onComplete)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let dismiss: DismissAction
        let onComplete: (CGImage?) -> Void

        init(dismiss: DismissAction, onComplete: @escaping (CGImage?) -> Void) {
            self.dismiss = dismiss
            self.onComplete = onComplete
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let uiImage = info[.originalImage] as? UIImage
            let cg = uiImage.flatMap { $0.cgImageApplyingDisplayOrientation() }
            dismiss()
            onComplete(cg)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
            onComplete(nil)
        }
    }
}
#endif
