//
//  ImageImportMetadata.swift
//  GlyphCanvas
//

import CoreLocation
import Foundation
import ImageIO
#if canImport(Photos)
import Photos
#endif

/// Carries bytes or references available at import time so titles can use EXIF / Photos metadata before PNG export strips it.
struct ImportHints: Sendable {
    var imageData: Data?
    var fileURL: URL?
    var photosLocalIdentifier: String?
    var sourcePageURL: URL?

    init(
        imageData: Data? = nil,
        fileURL: URL? = nil,
        photosLocalIdentifier: String? = nil,
        sourcePageURL: URL? = nil
    ) {
        self.imageData = imageData
        self.fileURL = fileURL
        self.photosLocalIdentifier = photosLocalIdentifier
        self.sourcePageURL = sourcePageURL
    }
}

enum ImageImportMetadata {
    struct Extracted: Sendable {
        var captureDate: Date?
        var coordinate: CLLocationCoordinate2D?
    }

    /// Reads EXIF / TIFF / GPS from embedded image data (JPEG, HEIC, TIFF, etc.).
    static func extract(from data: Data) -> Extracted {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return Extracted()
        }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return Extracted()
        }
        var out = Extracted()
        out.captureDate = parseCaptureDate(properties: props)
        out.coordinate = parseGPS(properties: props)
        return out
    }

    private static func parseCaptureDate(properties: [CFString: Any]) -> Date? {
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
               let d = parseExifDateTime(raw) {
                return d
            }
            if let raw = exif[kCGImagePropertyExifDateTimeDigitized] as? String,
               let d = parseExifDateTime(raw) {
                return d
            }
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let raw = tiff[kCGImagePropertyTIFFDateTime] as? String,
           let d = parseExifDateTime(raw) {
            return d
        }
        return nil
    }

    private static func parseExifDateTime(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let d = f.date(from: trimmed) { return d }
        f.dateFormat = "yyyy:MM:dd"
        return f.date(from: trimmed)
    }

    private static func parseGPS(properties: [CFString: Any]) -> CLLocationCoordinate2D? {
        guard let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] else {
            return nil
        }
        guard let lat = latitudeFromGPS(gps), let lon = longitudeFromGPS(gps) else {
            return nil
        }
        guard lat >= -90, lat <= 90, lon >= -180, lon <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private static func latitudeFromGPS(_ gps: [CFString: Any]) -> Double? {
        guard let v = doubleFromGPSComponent(gps[kCGImagePropertyGPSLatitude]) else { return nil }
        let ref = (gps[kCGImagePropertyGPSLatitudeRef] as? String) ?? "N"
        return ref.uppercased() == "S" ? -v : v
    }

    private static func longitudeFromGPS(_ gps: [CFString: Any]) -> Double? {
        guard let v = doubleFromGPSComponent(gps[kCGImagePropertyGPSLongitude]) else { return nil }
        let ref = (gps[kCGImagePropertyGPSLongitudeRef] as? String) ?? "E"
        return ref.uppercased() == "W" ? -v : v
    }

    private static func doubleFromGPSComponent(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        if let cg = value as? CGFloat { return Double(cg) }
        if let arr = value as? [NSNumber], arr.count == 3 {
            return Double(truncating: arr[0])
                + Double(truncating: arr[1]) / 60.0
                + Double(truncating: arr[2]) / 3600.0
        }
        return nil
    }
}

#if canImport(Photos)
enum PhotosAssetMetadataReader {
    /// Best-effort metadata from the user's library when a local identifier is available.
    static func fetch(localIdentifier: String) -> (date: Date?, location: CLLocation?) {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else {
            return (nil, nil)
        }
        return (asset.creationDate, asset.location)
    }
}
#endif

enum ImportTitleBuilder {
    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "MMM yyyy"
        return f
    }()

    /// Builds a provisional human prefix, optional location for reverse geocoding, and best capture date for merging with a place name later.
    static func provisionalPrefixAndLocation(hints: ImportHints?) -> (prefix: String?, location: CLLocation?, captureDate: Date?) {
        guard let hints else { return (nil, nil, nil) }

        var captureDate: Date?
        var location: CLLocation?

        #if canImport(Photos)
        if let pid = hints.photosLocalIdentifier, !pid.isEmpty {
            let meta = PhotosAssetMetadataReader.fetch(localIdentifier: pid)
            captureDate = meta.date
            location = meta.location
        }
        #endif

        if let data = hints.imageData {
            let ex = ImageImportMetadata.extract(from: data)
            if captureDate == nil { captureDate = ex.captureDate }
            if location == nil, let c = ex.coordinate {
                location = CLLocation(latitude: c.latitude, longitude: c.longitude)
            }
        }

        if captureDate == nil, let url = hints.fileURL {
            if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
               let mod = values.contentModificationDate {
                captureDate = mod
            }
        }

        let prefix = composePrefix(
            date: captureDate,
            locationLabel: nil,
            fallbackURL: hints.sourcePageURL,
            fileURL: hints.fileURL,
            weakFilenameOnly: captureDate == nil && location == nil
        )
        return (prefix, location, captureDate)
    }

    private static func composePrefix(
        date: Date?,
        locationLabel: String?,
        fallbackURL: URL?,
        fileURL: URL?,
        weakFilenameOnly: Bool
    ) -> String? {
        if let place = locationLabel, let d = date {
            let my = monthYearFormatter.string(from: d)
            let trimmed = place.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return "\(trimmed) — \(my)"
            }
        }
        if let d = date {
            return monthYearFormatter.string(from: d)
        }
        if weakFilenameOnly {
            if let name = sanitizedFilename(fallbackURL) ?? sanitizedFilename(fileURL) {
                return name
            }
        }
        return nil
    }

    /// Merges reverse-geocoded place with capture month/year.
    static func prefix(placeName: String, captureDate: Date?) -> String? {
        let trimmed = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let d = captureDate {
            let my = monthYearFormatter.string(from: d)
            return "\(trimmed) — \(my)"
        }
        return trimmed
    }

    private static func sanitizedFilename(_ url: URL?) -> String? {
        guard let url else { return nil }
        let last = url.lastPathComponent
        guard !last.isEmpty, last != "/" else { return nil }
        let base = (last as NSString).deletingPathExtension
        let cleaned = base
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 2, cleaned.count < 80 else { return nil }
        return cleaned
    }
}

enum ImportGeocoding {
    /// Reverse geocode; returns a locality / administrative area suitable for titles.
    static func placeLabel(for location: CLLocation) async -> String? {
        await withCheckedContinuation { cont in
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { placemarks, _ in
                guard let p = placemarks?.first else {
                    cont.resume(returning: nil)
                    return
                }
                if let locality = p.locality, !locality.isEmpty {
                    cont.resume(returning: locality)
                    return
                }
                if let sub = p.subAdministrativeArea, !sub.isEmpty {
                    cont.resume(returning: sub)
                    return
                }
                if let admin = p.administrativeArea, !admin.isEmpty {
                    cont.resume(returning: admin)
                    return
                }
                if let name = p.name, !name.isEmpty {
                    cont.resume(returning: name)
                    return
                }
                cont.resume(returning: nil)
            }
        }
    }
}
