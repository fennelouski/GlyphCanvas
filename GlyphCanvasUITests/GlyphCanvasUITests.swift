//
//  GlyphCanvasUITests.swift
//  GlyphCanvasUITests
//
//  Core workflows: Home → new artwork picker, and Studio live tuning → save.
//

import XCTest
#if canImport(UIKit)
import UIKit

final class GlyphCanvasUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Home's primary action opens Studio with the image source picker.
    @MainActor
    func testHomeNewArtworkOpensPicker() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-debugTab", "gallery"]
        app.launch()

        let choose = app.buttons["Choose a Photo"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10))
        choose.tap()

        XCTAssertTrue(app.buttons["Choose from Library"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Import from URL…"].exists)
    }

    /// With an image loaded, controls are live, the preview is on screen, and saving lands in the gallery.
    @MainActor
    func testStudioTuneAndSave() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-debugTab", "studio", "-debugLoadImagePath", try Self.writeSampleImage()]
        app.launch()

        let preview = app.otherElements["Artwork preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15))

        let detail = app.sliders["Detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        detail.adjust(toNormalizedSliderPosition: 0.9)
        app.buttons["Trace edges"].tap()

        // Preview must still be visible after interacting with controls.
        XCTAssertTrue(preview.isHittable)

        let save = app.buttons["Save to Gallery"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts["Saved to gallery."].waitForExistence(timeout: 10))

        app.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts["Gallery"].waitForExistence(timeout: 5))
    }

    private static func writeSampleImage() throws -> String {
        let size = CGSize(width: 320, height: 240)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.systemOrange.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 80, y: 40, width: 160, height: 160))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("glyphcanvas-uitest.png")
        try XCTUnwrap(image.pngData()).write(to: url)
        return url.path
    }
}
#endif
