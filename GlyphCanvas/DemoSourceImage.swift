//
//  DemoSourceImage.swift
//  GlyphCanvas
//

import CoreGraphics

enum DemoSourceImage {
    /// Grayscale mosaic used for “Try demo” — readable, portrait-friendly proportions.
    static func makeMosaicCGImage(width: Int = 512, height: Int = 640) -> CGImage? {
        guard let ctx = ImageProcessing.makeContext(width: width, height: height, data: nil) else {
            return nil
        }
        let cell: CGFloat = 6
        var state: UInt64 = 0xC0FFEE_D00D_BEEF
        for y in stride(from: 0, to: CGFloat(height), by: cell) {
            for x in stride(from: 0, to: CGFloat(width), by: cell) {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let g = CGFloat(state % 220) / 255.0 * 0.5 + 0.14
                ctx.setFillColor(gray: g, alpha: 1)
                let w = min(cell, CGFloat(width) - x)
                let h = min(cell, CGFloat(height) - y)
                ctx.fill(CGRect(x: x, y: y, width: w, height: h))
            }
        }
        return ctx.makeImage()
    }
}
