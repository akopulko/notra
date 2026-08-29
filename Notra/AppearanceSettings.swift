import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Stable UserDefaults keys for appearance choices shared by the editor and preview.
enum AppearanceSettingKey {
    static let editorFontName = "appearance.editorFontName"
    static let editorFontSize = "appearance.editorFontSize"
    static let previewFontName = "appearance.previewFontName"
    static let previewUsesEditorTheme = "appearance.previewUsesEditorTheme"
}

/// Converts the persisted font preference into SwiftUI and platform-native font values.
enum AppearanceFont {
    static let defaultName = ""
    static let defaultDisplayName = "System Default"
    static let defaultSize = 17.0

    static func editorFont(named fontName: String, size: Double) -> Font {
        let pointSize = CGFloat(size)

        guard !fontName.isEmpty else {
            if size == defaultSize {
                return .system(.body, design: .monospaced)
            }

            return .system(size: pointSize, design: .monospaced)
        }

        return .custom(fontName, size: pointSize, relativeTo: .body)
    }

    #if os(macOS)
    static func nativeEditorFont(named fontName: String, size: Double) -> NSFont {
        let pointSize = CGFloat(size)

        if !fontName.isEmpty, let font = NSFont(name: fontName, size: pointSize) {
            return font
        }

        return .monospacedSystemFont(ofSize: pointSize, weight: .regular)
    }
    #elseif os(iOS)
    static func nativeEditorFont(named fontName: String, size: Double) -> UIFont {
        let pointSize = CGFloat(size)

        if !fontName.isEmpty, let font = UIFont(name: fontName, size: pointSize) {
            return font
        }

        return .monospacedSystemFont(ofSize: pointSize, weight: .regular)
    }
    #endif

    static func bodyFont(named fontName: String) -> Font {
        guard !fontName.isEmpty else {
            return .body
        }

        return .custom(fontName, size: defaultSize, relativeTo: .body)
    }
}
