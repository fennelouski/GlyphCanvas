//
//  ImagePicker.swift
//  GlyphCanvas
//
//  Created by Codex on 4/16/26.
//

import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Allowed image types for open panel (macOS) and file importer (iPad).
enum StudioImageFileTypes {
    static let allowedContentTypes: [UTType] = [.png, .jpeg, .tiff, .gif, .bmp, .heic]
}

#if os(macOS)
enum StudioImageFileImport {
    /// Presents `NSOpenPanel` and decodes the first chosen image file.
    static func presentOpenPanel(onImagePicked: @escaping (CGImage, ImportHints?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = StudioImageFileTypes.allowedContentTypes
        panel.title = "Choose an image"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        guard
            let data = try? Data(contentsOf: url),
            let image = ImageProcessing.decodeCGImage(data: data)
        else {
            return
        }
        let hints = ImportHints(imageData: data, fileURL: url)
        onImagePicked(image, hints)
    }
}
#endif

struct PlatformImagePicker: View {
    let onImagePicked: (CGImage, ImportHints?) -> Void
    var autoPresentImagePicker: Binding<Bool>?

    init(onImagePicked: @escaping (CGImage, ImportHints?) -> Void, autoPresentImagePicker: Binding<Bool>? = nil) {
        self.onImagePicked = onImagePicked
        self.autoPresentImagePicker = autoPresentImagePicker
    }

    var body: some View {
#if os(iOS) || os(visionOS)
        IOSOrVisionImageSourceMenu(onImagePicked: onImagePicked, autoPresentImagePicker: autoPresentImagePicker) {
            Label("Select Image", systemImage: "photo")
        }
#elseif os(macOS)
        MacImageSourceMenu(onImagePicked: onImagePicked, autoPresentImagePicker: autoPresentImagePicker)
#else
        EmptyView()
#endif
    }
}

#if os(iOS) || os(visionOS)
import PhotosUI
#if os(iOS) && !os(visionOS)
import UIKit
#endif

/// Shared sheet listing library, optional camera, and URL import — used by `IOSOrVisionImageSourceMenu` and iPad wide auto-present.
struct IOSImageSourcePickerSheet: View {
    @Binding var pickerItem: PhotosPickerItem?
    @Binding var isPresented: Bool
    var onRequestURLImport: () -> Void
    /// iPhone / iPad only; omit on visionOS.
    var onRequestCamera: (() -> Void)?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PhotosPicker(
                        selection: $pickerItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                    }
#if os(iOS) && !os(visionOS)
                    if let onRequestCamera, UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            isPresented = false
                            onRequestCamera()
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                        }
                    }
#endif
                    Button {
                        isPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            onRequestURLImport()
                        }
                    } label: {
                        Label("Import from URL…", systemImage: "link")
                    }
                }
            }
            .navigationTitle("Select Image")
#if os(iOS) && !os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
#endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary, .tertiary)
                    }
                    .accessibilityLabel(String(localized: "Close"))
                }
            }
        }
    }
}

struct IOSOrVisionImageSourceMenu<Label: View>: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var showImageSourceSheet = false
    @State private var showURLSheet = false
#if os(iOS) && !os(visionOS)
    @State private var showCamera = false
#endif

    let onImagePicked: (CGImage, ImportHints?) -> Void
    var autoPresentImagePicker: Binding<Bool>?
    var usesBorderedProminentButtonStyle: Bool
    private let label: () -> Label

    init(
        onImagePicked: @escaping (CGImage, ImportHints?) -> Void,
        autoPresentImagePicker: Binding<Bool>? = nil,
        usesBorderedProminentButtonStyle: Bool = true,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.onImagePicked = onImagePicked
        self.autoPresentImagePicker = autoPresentImagePicker
        self.usesBorderedProminentButtonStyle = usesBorderedProminentButtonStyle
        self.label = label
    }

    private var autoPresentWatch: Bool {
        autoPresentImagePicker?.wrappedValue ?? false
    }

    var body: some View {
        Group {
            if usesBorderedProminentButtonStyle {
                Button {
                    showImageSourceSheet = true
                } label: {
                    label()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    showImageSourceSheet = true
                } label: {
                    label()
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showImageSourceSheet) {
            Group {
#if os(iOS) && !os(visionOS)
                IOSImageSourcePickerSheet(
                    pickerItem: $pickerItem,
                    isPresented: $showImageSourceSheet,
                    onRequestURLImport: {
                        showURLSheet = true
                    },
                    onRequestCamera: {
                        showCamera = true
                    }
                )
#else
                IOSImageSourcePickerSheet(
                    pickerItem: $pickerItem,
                    isPresented: $showImageSourceSheet,
                    onRequestURLImport: {
                        showURLSheet = true
                    },
                    onRequestCamera: nil
                )
#endif
            }
        }
        .onChange(of: pickerItem) { _, newValue in
            guard let newValue else { return }
            Task {
                guard
                    let data = try? await newValue.loadTransferable(type: Data.self),
                    let image = ImageProcessing.decodeCGImage(data: data)
                else {
                    return
                }
                let pid = newValue.itemIdentifier
                let hints = ImportHints(imageData: data, photosLocalIdentifier: pid)
                await MainActor.run {
                    onImagePicked(image, hints)
                    showImageSourceSheet = false
                    pickerItem = nil
                }
            }
        }
        .onChange(of: autoPresentWatch) { _, shouldPresent in
            guard shouldPresent else { return }
            autoPresentImagePicker?.wrappedValue = false
            showImageSourceSheet = true
        }
#if os(iOS) && !os(visionOS)
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker { cg in
                showCamera = false
                if let cg {
                    onImagePicked(cg, nil)
                }
            }
            .ignoresSafeArea()
        }
#endif
        .sheet(isPresented: $showURLSheet) {
            URLImportSheet(onImagePicked: { cg, hints in onImagePicked(cg, hints) })
        }
    }
}

#endif

#if os(macOS)
import PhotosUI

private struct MacImageSourceMenu: View {
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showURLSheet = false
    let onImagePicked: (CGImage, ImportHints?) -> Void
    var autoPresentImagePicker: Binding<Bool>?

    private var autoPresentWatch: Bool {
        autoPresentImagePicker?.wrappedValue ?? false
    }

    var body: some View {
        Menu {
            PhotosPicker(
                selection: $photosPickerItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Select from Photos", systemImage: "photo.on.rectangle")
            }
            Button {
                StudioImageFileImport.presentOpenPanel(onImagePicked: onImagePicked)
            } label: {
                Label("Select from files", systemImage: "doc")
            }
            Button {
                showURLSheet = true
            } label: {
                Label("Import from URL", systemImage: "link")
            }
        } label: {
            Label("Select Image", systemImage: "photo")
        }
        .buttonStyle(.borderedProminent)
        .onChange(of: photosPickerItem) { _, newValue in
            guard let newValue else { return }
            Task {
                guard
                    let data = try? await newValue.loadTransferable(type: Data.self),
                    let image = ImageProcessing.decodeCGImage(data: data)
                else {
                    return
                }
                let pid = newValue.itemIdentifier
                let hints = ImportHints(imageData: data, photosLocalIdentifier: pid)
                await MainActor.run {
                    onImagePicked(image, hints)
                    photosPickerItem = nil
                }
            }
        }
        .sheet(isPresented: $showURLSheet) {
            URLImportSheet(onImagePicked: { cg, hints in onImagePicked(cg, hints) })
        }
        .onChange(of: autoPresentWatch) { _, shouldPresent in
            guard shouldPresent else { return }
            autoPresentImagePicker?.wrappedValue = false
            StudioImageFileImport.presentOpenPanel(onImagePicked: onImagePicked)
        }
    }
}

#endif
