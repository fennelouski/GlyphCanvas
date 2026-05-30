//
//  URLImportSheets.swift
//  GlyphCanvas
//

import CoreGraphics
import SwiftUI
import WebImagePicker
#if os(iOS)
import UIKit
#endif

struct PageURLPickItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Shared async URL → image / HTML branch used by `URLImportSheet` and `WideStudioEmptyImportView`.
enum URLImportFlow {
    enum Step {
        case decodedImage(CGImage, ImportHints?)
        case htmlPage(URL)
        case failed(String)
    }

    static func load(urlText: String) async -> Step {
        guard let parsed = URLImageImportHelpers.normalizedHTTPURL(from: urlText) else {
            return .failed(URLImageImportError.invalidURL.errorDescription ?? "Invalid URL.")
        }
        guard URLImageImportHelpers.isAllowedHTTPURL(parsed) else {
            return .failed(URLImageImportError.notHTTPOrHTTPS.errorDescription ?? "Only http and https URLs are supported.")
        }

        let outcome = await URLImageImportService.fetchOutcome(from: parsed)
        switch outcome {
        case .decodedImage(let cg, let hints):
            return .decodedImage(cg, hints)
        case .htmlPage(let pageURL):
            return .htmlPage(pageURL)
        case .failed(let err):
            return .failed(err.localizedDescription)
        }
    }
}

/// Decodes package selections into the app’s `CGImage` + `ImportHints` pipeline.
enum WebImageImportBridge {
    static func cgImageAndImportHints(from selection: WebImageSelection) -> (CGImage, ImportHints)? {
        let data: Data
        if !selection.data.isEmpty {
            data = selection.data
        } else if let file = selection.temporaryFileURL, let fileData = try? Data(contentsOf: file) {
            data = fileData
        } else {
            return nil
        }
        guard !data.isEmpty, let cg = ImageProcessing.decodeCGImage(data: data) else { return nil }
        return (cg, ImportHints(imageData: data, sourcePageURL: selection.sourceURL))
    }
}

/// Web page image discovery via `WebImagePicker` when `URLImportFlow` detects HTML.
///
/// - http + https to match `URLImageImportHelpers`.
/// - `extractionMode: .webView` for pages that inject images at runtime (replaces the old hidden `WKWebView` scraper).
/// - `initialURLString` plus `automaticallyLoadOnAppear` so discovery starts immediately with the resolved page URL (no extra manual load step).
struct GlyphCanvasWebImagePagePicker: View {
    let pageURL: URL
    var onCancel: () -> Void
    var onImagePicked: (CGImage, ImportHints?) -> Void

    var body: some View {
        WebImagePicker(
            configuration: webImageConfiguration,
            onCancel: onCancel,
            onPick: { selections in
                guard let first = selections.first,
                      let result = WebImageImportBridge.cgImageAndImportHints(from: first) else { return }
                onImagePicked(result.0, result.1)
            }
        )
#if os(macOS)
        .frame(minWidth: 480, minHeight: 400)
#endif
    }

    private var webImageConfiguration: WebImagePickerConfiguration {
        WebImagePickerConfiguration(
            allowedURLSchemes: ["http", "https"],
            extractionMode: .webView,
            initialURLString: pageURL.absoluteString,
            automaticallyLoadOnAppear: true
        )
    }
}

struct URLImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pagePickItem: PageURLPickItem?
#if os(iOS)
    @FocusState private var isURLFieldFocused: Bool
#endif

    let onImagePicked: (CGImage, ImportHints?) -> Void

    private var trimmedURLText: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmitLoad: Bool {
        !trimmedURLText.isEmpty && !isLoading
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $urlText)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .focused($isURLFieldFocused)
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
            .onAppear {
                DispatchQueue.main.async {
                    isURLFieldFocused = true
                }
            }
#endif
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Paste") {
                        pasteURLFromClipboard()
                    }
                    Spacer()
                    Button("Load") {
                        Task { await load() }
                    }
                    .disabled(!canSubmitLoad)
                }
#else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Load") { Task { await load() } }
                        .disabled(!canSubmitLoad)
                }
#endif
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
            GlyphCanvasWebImagePagePicker(pageURL: item.url) {
                pagePickItem = nil
            } onImagePicked: { cgImage, hints in
                onImagePicked(cgImage, hints)
                pagePickItem = nil
                dismiss()
            }
        }
    }

#if os(iOS)
    private func pasteURLFromClipboard() {
        guard let s = UIPasteboard.general.string else { return }
        urlText = s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
#endif

    private func load() async {
        errorMessage = nil
        isLoading = true
        let step = await URLImportFlow.load(urlText: urlText)
        isLoading = false

        switch step {
        case .decodedImage(let cg, let hints):
            onImagePicked(cg, hints)
            dismiss()
        case .htmlPage(let pageURL):
            pagePickItem = PageURLPickItem(url: pageURL)
        case .failed(let message):
            errorMessage = message
        }
    }
}
