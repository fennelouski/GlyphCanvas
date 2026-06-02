//
//  WebImagePickerUIQueries.swift
//  GlyphCanvasUITests
//
//  WebImagePicker (1.3.0+) shows SF Symbols in the toolbar; XCUI matches accessibility
//  labels (or identifiers), not visible button titles.
//

import XCTest

/// English accessibility labels from WebImagePicker `en.lproj` (`webimage.*` keys).
/// Run UI tests with `-AppleLanguages (en)` when asserting these strings.
enum WebImagePickerAccessibility {
    static let cancel = "Cancel"
    static let done = "Done"
    static let loadPage = "Load page"
    static let loading = "Loading"
    static let changeURL = "Change URL"
    static let navTitle = "Web images"

    static let imageMetadataSearch = "webimage.imageMetadataSearch"
    static let aggregationNotice = "webimage.aggregationNotice"
    static let httpSkippedImagesNotice = "webimage.httpSkippedImagesNotice"
    static let browsingDownloadError = "webimage.browsingDownloadError"
}

extension XCUIApplication {
    var webImagePickerCancelButton: XCUIElement { buttons[WebImagePickerAccessibility.cancel] }
    var webImagePickerDoneButton: XCUIElement { buttons[WebImagePickerAccessibility.done] }
    var webImagePickerLoadPageButton: XCUIElement { buttons[WebImagePickerAccessibility.loadPage] }
    var webImagePickerChangeURLButton: XCUIElement { buttons[WebImagePickerAccessibility.changeURL] }

    var webImagePickerImageMetadataSearchField: XCUIElement {
        textFields[WebImagePickerAccessibility.imageMetadataSearch]
    }
}
