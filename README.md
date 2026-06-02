# GlyphCanvas

GlyphCanvas is a SwiftUI app for turning source images into evolving glyph-based artwork. It includes a live Studio for encoding and tuning output, plus a Gallery for browsing, resuming, and exporting saved pieces.

## Features

- Import images from files or URLs
- Evolve artwork using glyph-based optimization
- Tune generation controls (speed, region size, candidate count, fidelity)
- Scrub and play back glyph timeline history
- Save and manage artworks in the built-in Gallery
- Export rendered results and related assets

## Project Structure

- `GlyphCanvas/` - App source code
- `GlyphCanvasTests/` - Unit tests
- `GlyphCanvasUITests/` - UI tests
- `Graphics/` - Graphics-related assets/resources
- `GlyphCanvas.xcodeproj/` - Xcode project

## Getting Started

1. Open `GlyphCanvas.xcodeproj` in Xcode.
2. Select the `GlyphCanvas` scheme.
3. Build and run on your target Apple platform.

## Development

- Built with Swift and SwiftUI
- Uses standard Xcode test targets for validation

### WebImagePicker (HTML URL import)

The app depends on [WebImagePicker](https://github.com/fennelouski/SwiftUI-Web-Image-Picker) via Swift Package Manager (currently resolved to **1.3.0** in `Package.resolved`, requirement **Up to Next Major** from 1.3.0). Toolbar actions use SF Symbols with localized accessibility labels; the app targets the package’s public API (`WebImagePicker`, `WebImagePickerConfiguration`, `WebImageSelection`).

HTML pages open `GlyphCanvasWebImagePagePicker`, a thin wrapper around `WebImagePicker(configuration:onCancel:onPick:)` with `automaticallyLoadOnAppear`.

**UI tests:** Query WebImagePicker controls by accessibility label (e.g. `Cancel`, `Done`, `Load page` in English) or by identifier where exposed (`webimage.imageMetadataSearch`, etc.). See `GlyphCanvasUITests/WebImagePickerUIQueries.swift`. Do not match on visible toolbar text.

## License

No license has been added yet. If you plan to distribute this project, add a license file (for example, MIT, Apache-2.0, or GPL-3.0).
