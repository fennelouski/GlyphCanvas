//
//  URLImageImport.swift
//  GlyphCanvas
//

import CoreGraphics
import Foundation

enum URLImageImportError: LocalizedError, Equatable {
    case invalidURL
    case notHTTPOrHTTPS
    case httpStatus(Int)
    case bodyTooLarge
    case notImageAndNotHTML
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That doesn’t look like a valid URL."
        case .notHTTPOrHTTPS:
            return "Only http and https URLs are supported."
        case .httpStatus(let code):
            return "The server returned an error (HTTP \(code))."
        case .bodyTooLarge:
            return "The download is too large."
        case .notImageAndNotHTML:
            return "Couldn’t load an image from this address."
        case .network(let message):
            return message
        }
    }
}

enum URLImageFetchOutcome {
    case decodedImage(CGImage)
    case htmlPage(URL)
    case failed(URLImageImportError)
}

enum URLImageImportHelpers {
    /// Trims whitespace; if the string has no scheme, prepends `https://`.
    static func normalizedHTTPURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let u = URL(string: trimmed), u.scheme != nil {
            return u
        }
        return URL(string: "https://\(trimmed)")
    }

    static func isAllowedHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// Resolves relative strings against `baseURL`, keeps only http(s), preserves first-seen order.
    static func resolvedHTTPSURLs(strings: [String], baseURL: URL) -> [URL] {
        var seen = Set<String>()
        var out: [URL] = []
        for s in strings {
            guard let resolved = URL(string: s, relativeTo: baseURL)?.absoluteURL else { continue }
            guard isAllowedHTTPURL(resolved) else { continue }
            let key = resolved.absoluteString
            if seen.insert(key).inserted {
                out.append(resolved)
            }
        }
        return out
    }

    static func sniffsHTML(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(512), encoding: .utf8)?.lowercased() else { return false }
        return prefix.contains("<!doctype html") || prefix.contains("<html")
    }

    /// Clearer than raw `URLError.localizedDescription` for common cases (DNS, offline, timeout).
    static func userFacingNetworkMessage(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed:
            return "No internet connection. Check Wi‑Fi or cellular, then try again."
        case .cannotFindHost, .dnsLookupFailed:
            return "Couldn’t reach that host (DNS). Check Wi‑Fi, try without VPN, or open this URL in Safari.\nIf Safari also fails, fix your network or DNS—not GlyphCanvas."
        case .timedOut:
            return "The request timed out. Check your connection and try again."
        case .networkConnectionLost:
            return "The network connection was lost. Try again."
        case .cannotConnectToHost:
            return "Couldn’t connect to that server. It may be unreachable or temporarily down."
        default:
            return error.localizedDescription
        }
    }
}

enum URLImageImportService {
    nonisolated static let maxDownloadBytes = 12 * 1024 * 1024

    static func fetchOutcome(from url: URL) async -> URLImageFetchOutcome {
        guard URLImageImportHelpers.isAllowedHTTPURL(url) else {
            return .failed(.notHTTPOrHTTPS)
        }
        do {
            let (data, http) = try await dataWithSizeLimit(from: url, maxBytes: maxDownloadBytes)
            let status = http.statusCode
            guard (200..<300).contains(status) else {
                return .failed(.httpStatus(status))
            }
            let finalURL = http.url ?? url
            if let image = ImageProcessing.decodeCGImage(data: data) {
                return .decodedImage(image)
            }
            let mime = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            if mime.contains("text/html") || URLImageImportHelpers.sniffsHTML(data) {
                return .htmlPage(finalURL)
            }
            return .failed(.notImageAndNotHTML)
        } catch let e as URLError {
            return .failed(.network(URLImageImportHelpers.userFacingNetworkMessage(for: e)))
        } catch let importErr as URLImageImportError {
            return .failed(importErr)
        } catch {
            return .failed(.network(error.localizedDescription))
        }
    }

    static func fetchImageData(from url: URL, maxBytes: Int = maxDownloadBytes) async -> Result<Data, URLImageImportError> {
        guard URLImageImportHelpers.isAllowedHTTPURL(url) else {
            return .failure(.notHTTPOrHTTPS)
        }
        do {
            let (data, http) = try await dataWithSizeLimit(from: url, maxBytes: maxBytes)
            guard (200..<300).contains(http.statusCode) else {
                return .failure(.httpStatus(http.statusCode))
            }
            return .success(data)
        } catch let e as URLError {
            return .failure(.network(URLImageImportHelpers.userFacingNetworkMessage(for: e)))
        } catch let importErr as URLImageImportError {
            return .failure(importErr)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    static func dataWithSizeLimit(from url: URL, maxBytes: Int) async throws -> (Data, HTTPURLResponse) {
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        var data = Data()
        data.reserveCapacity(min(maxBytes, 256 * 1024))
        for try await byte in asyncBytes {
            data.append(byte)
            if data.count > maxBytes {
                throw URLImageImportError.bodyTooLarge
            }
        }
        return (data, http)
    }
}
