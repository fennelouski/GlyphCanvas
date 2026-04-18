//
//  URLImportSheets.swift
//  GlyphCanvas
//

import CoreGraphics
import SwiftUI

private struct PageURLItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct URLImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pagePickItem: PageURLItem?

    let onImagePicked: (CGImage) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $urlText)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                } header: {
                    Text("Image URL")
                } footer: {
                    Text("We load the address directly first. If it’s a webpage, you can choose an image from the page.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle("Import from URL")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Load") { Task { await load() } }
                        .disabled(isLoading || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .overlay {
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.15)
                        ProgressView()
                            .padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .ignoresSafeArea()
                }
            }
        }
        .padding(20)
#if os(macOS)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 240)
#endif
        .sheet(item: $pagePickItem) { item in
            PageImagesFromWebSheet(pageURL: item.url) { cgImage in
                onImagePicked(cgImage)
                pagePickItem = nil
                dismiss()
            }
        }
    }

    private func load() async {
        errorMessage = nil
        guard let parsed = URLImageImportHelpers.normalizedHTTPURL(from: urlText) else {
            errorMessage = URLImageImportError.invalidURL.errorDescription
            return
        }
        guard URLImageImportHelpers.isAllowedHTTPURL(parsed) else {
            errorMessage = URLImageImportError.notHTTPOrHTTPS.errorDescription
            return
        }

        isLoading = true
        let outcome = await URLImageImportService.fetchOutcome(from: parsed)
        isLoading = false

        switch outcome {
        case .decodedImage(let cg):
            onImagePicked(cg)
            dismiss()
        case .htmlPage(let pageURL):
            pagePickItem = PageURLItem(url: pageURL)
        case .failed(let err):
            errorMessage = err.localizedDescription
        }
    }
}

struct PageImagesFromWebSheet: View {
    @Environment(\.dismiss) private var dismiss

    let pageURL: URL
    let onImagePicked: (CGImage) -> Void

    @State private var phase: Phase = .loadingWeb
    @State private var imageURLs: [URL] = []
    @State private var webError: String?
    @State private var selectedDownloadError: String?
    @State private var isFetchingImage = false

    private enum Phase {
        case loadingWeb
        case picking
    }

    var body: some View {
        NavigationStack {
            ZStack {
                hiddenWebLoader
                content
            }
            .navigationTitle("Images on page")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if isFetchingImage {
                    ZStack {
                        Color.black.opacity(0.15)
                        ProgressView("Loading image…")
                            .padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .ignoresSafeArea()
                }
            }
        }
    }

    @ViewBuilder
    private var hiddenWebLoader: some View {
        PageImageWebView(
            url: pageURL,
            onImageURLStrings: { strings in
                let resolved = URLImageImportHelpers.resolvedHTTPSURLs(strings: strings, baseURL: pageURL)
                imageURLs = resolved
                if resolved.isEmpty {
                    webError = "No images found on this page."
                    phase = .picking
                } else {
                    webError = nil
                    phase = .picking
                }
            },
            onFailure: { error in
                webError = error.localizedDescription
                phase = .picking
            }
        )
        .frame(width: 1, height: 1)
        .opacity(0.01)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loadingWeb:
            ContentUnavailableView {
                Label("Loading page", systemImage: "globe")
            } description: {
                Text("Fetching images from the page…")
            }
        case .picking:
            if let webError {
                ContentUnavailableView {
                    Label("Couldn’t load images", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(webError)
                }
            } else if imageURLs.isEmpty {
                ContentUnavailableView {
                    Label("No images", systemImage: "photo")
                } description: {
                    Text("No images found on this page.")
                }
            } else {
                ScrollView {
                    if let selectedDownloadError {
                        Text(selectedDownloadError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 8)
                    }
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 100), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(imageURLs, id: \.self) { imageURL in
                            Button {
                                Task { await pick(url: imageURL) }
                            } label: {
                                PageImageThumbnail(url: imageURL)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func pick(url: URL) async {
        selectedDownloadError = nil
        isFetchingImage = true
        let result = await URLImageImportService.fetchImageData(from: url)
        isFetchingImage = false
        switch result {
        case .success(let data):
            guard let cg = ImageProcessing.decodeCGImage(data: data) else {
                selectedDownloadError = "Couldn’t decode this image."
                return
            }
            onImagePicked(cg)
        case .failure(let err):
            selectedDownloadError = err.localizedDescription
        }
    }
}

private struct PageImageThumbnail: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.15))
                    ProgressView()
                }
                .frame(minWidth: 100, minHeight: 100)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 100, minHeight: 100)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            case .failure:
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.15))
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 100, minHeight: 100)
            @unknown default:
                EmptyView()
            }
        }
    }
}
