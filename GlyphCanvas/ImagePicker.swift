//
//  ImagePicker.swift
//  GlyphCanvas
//
//  Created by Codex on 4/16/26.
//

import CoreGraphics
import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct PlatformImagePicker: View {
    let onImagePicked: (CGImage) -> Void
    var autoPresentImagePicker: Binding<Bool>?

    init(onImagePicked: @escaping (CGImage) -> Void, autoPresentImagePicker: Binding<Bool>? = nil) {
        self.onImagePicked = onImagePicked
        self.autoPresentImagePicker = autoPresentImagePicker
    }

    var body: some View {
#if os(iOS) || os(visionOS)
        IOSOrVisionImageSourceMenu(onImagePicked: onImagePicked, autoPresentImagePicker: autoPresentImagePicker)
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

private struct IOSOrVisionImageSourceMenu: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var showImageSourceSheet = false
    @State private var showURLSheet = false
#if os(iOS) && !os(visionOS)
    @State private var showCamera = false
#endif

    let onImagePicked: (CGImage) -> Void
    var autoPresentImagePicker: Binding<Bool>?

    private var autoPresentWatch: Bool {
        autoPresentImagePicker?.wrappedValue ?? false
    }

    var body: some View {
        Button {
            showImageSourceSheet = true
        } label: {
            Label("Select Image", systemImage: "photo")
        }
        .buttonStyle(.borderedProminent)
        .sheet(isPresented: $showImageSourceSheet) {
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
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button {
                                showImageSourceSheet = false
                                showCamera = true
                            } label: {
                                Label("Take Photo", systemImage: "camera")
                            }
                        }
#endif
                        Button {
                            showImageSourceSheet = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                showURLSheet = true
                            }
                        } label: {
                            Label("Import from URL…", systemImage: "link")
                        }
                    }
                }
                .navigationTitle("Select Image")
                #if os(iOS) && !os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showImageSourceSheet = false
                        }
                    }
                }
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
                await MainActor.run {
                    onImagePicked(image)
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
                    onImagePicked(cg)
                }
            }
            .ignoresSafeArea()
        }
#endif
        .sheet(isPresented: $showURLSheet) {
            URLImportSheet(onImagePicked: onImagePicked)
        }
    }
}

#endif

#if os(macOS)
import PhotosUI

private struct MacImageSourceMenu: View {
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showURLSheet = false
    let onImagePicked: (CGImage) -> Void
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
                openFilesPanel()
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
                await MainActor.run {
                    onImagePicked(image)
                    photosPickerItem = nil
                }
            }
        }
        .sheet(isPresented: $showURLSheet) {
            URLImportSheet(onImagePicked: onImagePicked)
        }
        .onChange(of: autoPresentWatch) { _, shouldPresent in
            guard shouldPresent else { return }
            autoPresentImagePicker?.wrappedValue = false
            openFilesPanel()
        }
    }

    private func openFilesPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .bmp, .heic]
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
        onImagePicked(image)
    }
}

#endif
