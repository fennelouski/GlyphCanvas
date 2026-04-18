//
//  AppRoute.swift
//  GlyphCanvas
//

import Foundation

enum AppRoute: Hashable {
    case detail(UUID)
    case editorNew
    case editorResume(UUID)
}
