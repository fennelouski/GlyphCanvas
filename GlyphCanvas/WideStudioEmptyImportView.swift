//
//  WideStudioEmptyImportView.swift
//  GlyphCanvas
//

import CoreGraphics
import PhotosUI
import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(macOS) || os(iOS)

/// Full-width empty-Studio import chrome for macOS and iPad: Photos / Files / URL bar.
struct WideStudioEmptyImportView: View {
    let onImagePicked: (CGImage, ImportHints?) -> Void
    var autoPresentImagePicker: Binding<Bool>?

    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var urlText = ""
    @State private var isLoadingURL = false
    @State private var urlError: String?
    @State private var pagePickItem: PageURLPickItem?
    @State private var showURLSheet = false
    /// iPad “New mosaic” auto-present: same list as phone (`IOSImageSourcePickerSheet`); Photos can’t be opened programmatically.
    @State private var showAutoPresentSheet = false
    @State private var autoPresentPickerItem: PhotosPickerItem?
#if os(iOS)
    @State private var showCamera = false
#endif

    private var autoPresentWatch: Bool {
        autoPresentImagePicker?.wrappedValue ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 16) {
                largePhotosButton
                largeFilesButton
            }
            .padding(.horizontal, 4)
            Spacer(minLength: 20)
            urlImportBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: photosPickerItem) { _, newValue in
            consumePhotosItem(newValue) {
                photosPickerItem = nil
            }
        }
        .onChange(of: autoPresentPickerItem) { _, newValue in
            consumePhotosItem(newValue) {
                autoPresentPickerItem = nil
                showAutoPresentSheet = false
            }
        }
#if os(iOS)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: StudioImageFileTypes.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            importFromFileImporterResult(result)
        }
#endif
        .onChange(of: autoPresentWatch) { _, shouldPresent in
            guard shouldPresent else { return }
            autoPresentImagePicker?.wrappedValue = false
#if os(macOS)
            StudioImageFileImport.presentOpenPanel(onImagePicked: onImagePicked)
#elseif os(iOS)
            showAutoPresentSheet = true
#endif
        }
#if os(iOS)
        .sheet(isPresented: $showAutoPresentSheet) {
            IOSImageSourcePickerSheet(
                pickerItem: $autoPresentPickerItem,
                isPresented: $showAutoPresentSheet,
                onRequestURLImport: {
                    showURLSheet = true
                },
                onRequestCamera: { showCamera = true }
            )
        }
        .sheet(isPresented: $showURLSheet) {
            URLImportSheet(onImagePicked: { cg, hints in onImagePicked(cg, hints) })
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker { cg in
                showCamera = false
                showAutoPresentSheet = false
                if let cg {
                    onImagePicked(cg, nil)
                }
            }
            .ignoresSafeArea()
        }
#endif
        .sheet(item: $pagePickItem) { item in
            PageImagesFromWebSheet(pageURL: item.url) { cg, hints in
                onImagePicked(cg, hints)
                pagePickItem = nil
            }
        }
    }

    private var largePhotosButton: some View {
        PhotosPicker(
            selection: $photosPickerItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 36, weight: .semibold))
                Text("Photos")
                    .font(.headline.weight(.heavy))
                    .tracking(0.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .foregroundStyle(GalleryTheme.onAccentFill)
            .background(GalleryTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var largeFilesButton: some View {
        Button {
#if os(macOS)
            StudioImageFileImport.presentOpenPanel(onImagePicked: onImagePicked)
#else
            showFileImporter = true
#endif
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 36, weight: .semibold))
                Text("Files")
                    .font(.headline.weight(.heavy))
                    .tracking(0.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .foregroundStyle(GalleryTheme.onAccentFill)
            .background(GalleryTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var urlImportBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                TextField("https://…", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif
                    .onSubmit { Task { await loadFromURLField() } }
                Button("Load") {
                    Task { await loadFromURLField() }
                }
                .buttonStyle(.borderedProminent)
                .tint(GalleryTheme.accent)
                .foregroundStyle(GalleryTheme.onAccentFill)
                .disabled(isLoadingURL || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let urlError {
                Text(urlError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
        .overlay {
            if isLoadingURL {
                ZStack {
                    Color.black.opacity(0.12)
                    ProgressView()
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func consumePhotosItem(_ newValue: PhotosPickerItem?, reset: @escaping () -> Void) {
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
                reset()
            }
        }
    }

#if os(iOS)
    private func importFromFileImporterResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            guard
                let data = try? Data(contentsOf: url),
                let cg = ImageProcessing.decodeCGImage(data: data)
            else {
                return
            }
            let hints = ImportHints(imageData: data, fileURL: url)
            onImagePicked(cg, hints)
        case .failure:
            break
        }
    }
#endif

    private func loadFromURLField() async {
        urlError = nil
        isLoadingURL = true
        let step = await URLImportFlow.load(urlText: urlText)
        isLoadingURL = false
        switch step {
        case .decodedImage(let cg, let hints):
            onImagePicked(cg, hints)
        case .htmlPage(let u):
            pagePickItem = PageURLPickItem(url: u)
        case .failed(let message):
            urlError = message
        }
    }
}

#endif
