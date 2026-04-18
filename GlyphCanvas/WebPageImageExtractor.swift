//
//  WebPageImageExtractor.swift
//  GlyphCanvas
//

import Foundation
import SwiftUI
import WebKit

#if os(iOS) || os(visionOS)
import UIKit

struct PageImageWebView: UIViewRepresentable {
    let url: URL
    let onImageURLStrings: ([String]) -> Void
    let onFailure: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageURLStrings: onImageURLStrings, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedPageURL != url {
            context.coordinator.loadedPageURL = url
            context.coordinator.hasCompleted = false
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var webView: WKWebView?
        var loadedPageURL: URL?
        var hasCompleted = false
        let onImageURLStrings: ([String]) -> Void
        let onFailure: (Error) -> Void

        init(onImageURLStrings: @escaping ([String]) -> Void, onFailure: @escaping (Error) -> Void) {
            self.onImageURLStrings = onImageURLStrings
            self.onFailure = onFailure
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            extract(from: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard !hasCompleted else { return }
            hasCompleted = true
            onFailure(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard !hasCompleted else { return }
            hasCompleted = true
            onFailure(error)
        }

        private func extract(from webView: WKWebView) {
            let js = Self.collectImageURLsJavaScript
            webView.evaluateJavaScript(js) { [weak self] result, error in
                guard let self else { return }
                guard !self.hasCompleted else { return }
                self.hasCompleted = true
                if let error {
                    self.onFailure(error)
                    return
                }
                if let arr = result as? [String] {
                    self.onImageURLStrings(arr)
                    return
                }
                if let single = result as? String {
                    self.onImageURLStrings([single])
                    return
                }
                self.onImageURLStrings([])
            }
        }

        private static let collectImageURLsJavaScript = """
        (function() {
          var urls = [];
          function push(u) {
            if (u && typeof u === 'string' && u.length > 0) urls.push(u);
          }
          var og = document.querySelector('meta[property="og:image"]');
          if (og) push(og.getAttribute('content'));
          og = document.querySelector('meta[name="twitter:image"]');
          if (og) push(og.getAttribute('content'));
          var list = document.images;
          for (var i = 0; i < list.length; i++) {
            var im = list[i];
            push(im.currentSrc || im.src);
          }
          return urls;
        })()
        """
    }
}

#endif

#if os(macOS)
import AppKit

struct PageImageWebView: NSViewRepresentable {
    let url: URL
    let onImageURLStrings: ([String]) -> Void
    let onFailure: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageURLStrings: onImageURLStrings, onFailure: onFailure)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedPageURL != url {
            context.coordinator.loadedPageURL = url
            context.coordinator.hasCompleted = false
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var webView: WKWebView?
        var loadedPageURL: URL?
        var hasCompleted = false
        let onImageURLStrings: ([String]) -> Void
        let onFailure: (Error) -> Void

        init(onImageURLStrings: @escaping ([String]) -> Void, onFailure: @escaping (Error) -> Void) {
            self.onImageURLStrings = onImageURLStrings
            self.onFailure = onFailure
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            extract(from: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard !hasCompleted else { return }
            hasCompleted = true
            onFailure(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard !hasCompleted else { return }
            hasCompleted = true
            onFailure(error)
        }

        private func extract(from webView: WKWebView) {
            let js = Self.collectImageURLsJavaScript
            webView.evaluateJavaScript(js) { [weak self] result, error in
                guard let self else { return }
                guard !self.hasCompleted else { return }
                self.hasCompleted = true
                if let error {
                    self.onFailure(error)
                    return
                }
                if let arr = result as? [String] {
                    self.onImageURLStrings(arr)
                    return
                }
                if let single = result as? String {
                    self.onImageURLStrings([single])
                    return
                }
                self.onImageURLStrings([])
            }
        }

        private static let collectImageURLsJavaScript = """
        (function() {
          var urls = [];
          function push(u) {
            if (u && typeof u === 'string' && u.length > 0) urls.push(u);
          }
          var og = document.querySelector('meta[property="og:image"]');
          if (og) push(og.getAttribute('content'));
          og = document.querySelector('meta[name="twitter:image"]');
          if (og) push(og.getAttribute('content'));
          var list = document.images;
          for (var i = 0; i < list.length; i++) {
            var im = list[i];
            push(im.currentSrc || im.src);
          }
          return urls;
        })()
        """
    }
}

#endif
