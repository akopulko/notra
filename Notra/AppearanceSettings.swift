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
    /// Controls whether note rows include their content preview below the title or first line.
    static let showsNotePreview = "appearance.showsNotePreview"
}

/// A selectable installed font family with its regular face as the persisted value.
struct AppearanceFontChoice: Identifiable, Hashable {
    let fontName: String
    let displayName: String
    private let familyFontNames: Set<String>

    init(fontName: String, displayName: String, familyFontNames: Set<String> = []) {
        self.fontName = fontName
        self.displayName = displayName
        self.familyFontNames = familyFontNames.union([fontName])
    }

    var id: String {
        fontName
    }

    /// Matches legacy saved variants so they can return to the family's regular face.
    func containsFontName(_ name: String) -> Bool {
        familyFontNames.contains(name)
    }
}

/// Converts the persisted font preference into SwiftUI and platform-native font values.
enum AppearanceFont {
    static let defaultName = ""
    static let defaultDisplayName = "System Default"
    static let defaultSize = 17.0

    private static var availableChoicesCache: [Bool: [AppearanceFontChoice]] = [:]

    /// Returns the installed font families appropriate for one appearance preference.
    ///
    /// The empty name remains the durable representation of the system default, while
    /// concrete choices persist each family's regular PostScript name.
    static func availableChoices(fixedPitchOnly: Bool) -> [AppearanceFontChoice] {
        if let cachedChoices = availableChoicesCache[fixedPitchOnly] {
            return cachedChoices
        }

        let familyNames: [String]

        #if os(macOS)
        familyNames = NSFontManager.shared.availableFontFamilies
        #elseif os(iOS)
        familyNames = UIFont.familyNames
        #endif

        let installedChoices = Set<String>(familyNames).compactMap { familyName in
            choice(forFamily: familyName, fixedPitchOnly: fixedPitchOnly)
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

        let choices = [AppearanceFontChoice(fontName: defaultName, displayName: defaultDisplayName)] + installedChoices
        availableChoicesCache[fixedPitchOnly] = choices
        return choices
    }

    /// Clears the catalogue so the next settings presentation sees newly installed fonts.
    static func invalidateAvailableChoices() {
        availableChoicesCache.removeAll(keepingCapacity: true)
    }

    /// Resolves stale UserDefaults values to the explicit system-default menu choice.
    static func resolvedName(_ fontName: String, choices: [AppearanceFontChoice]) -> String {
        guard let choice = choices.first(where: { $0.containsFontName(fontName) }) else {
            return defaultName
        }

        return choice.fontName
    }

    static func editorFont(named fontName: String, size: Double) -> Font {
        let pointSize = CGFloat(size)

        guard !fontName.isEmpty else {
            if size == defaultSize {
                return .system(.body, design: .monospaced)
            }

            return .system(size: pointSize, design: .monospaced)
        }

        guard isInstalled(fontName) else {
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

        guard isInstalled(fontName) else {
            return .body
        }

        return .custom(fontName, size: defaultSize, relativeTo: .body)
    }

    #if os(macOS)
    private static func choice(forFamily familyName: String, fixedPitchOnly: Bool) -> AppearanceFontChoice? {
        guard let font = NSFontManager.shared.font(
            withFamily: familyName,
            traits: [],
            weight: 5,
            size: CGFloat(defaultSize)
        ), !fixedPitchOnly || isFixedPitch(font)
        else {
            return nil
        }

        let familyFontNames = NSFontManager.shared.availableMembers(ofFontFamily: familyName)?
            .compactMap { $0.first as? String } ?? []
        return AppearanceFontChoice(
            fontName: font.fontName,
            displayName: familyName,
            familyFontNames: Set(familyFontNames)
        )
    }

    private static func platformFont(named fontName: String) -> NSFont? {
        NSFont(name: fontName, size: CGFloat(defaultSize))
    }

    private static func isFixedPitch(_ font: NSFont) -> Bool {
        font.isFixedPitch
    }

    #elseif os(iOS)
    private static func choice(forFamily familyName: String, fixedPitchOnly: Bool) -> AppearanceFontChoice? {
        let descriptor = UIFontDescriptor(fontAttributes: [.family: familyName])
        let font = UIFont(descriptor: descriptor, size: CGFloat(defaultSize))

        guard !fixedPitchOnly || isFixedPitch(font) else {
            return nil
        }

        return AppearanceFontChoice(
            fontName: font.fontName,
            displayName: familyName,
            familyFontNames: Set(UIFont.fontNames(forFamilyName: familyName))
        )
    }

    private static func platformFont(named fontName: String) -> UIFont? {
        UIFont(name: fontName, size: CGFloat(defaultSize))
    }

    private static func isFixedPitch(_ font: UIFont) -> Bool {
        font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
    }

    #endif

    private static func isInstalled(_ fontName: String) -> Bool {
        platformFont(named: fontName) != nil
    }
}
