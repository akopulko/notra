import Foundation
import SwiftUI

#if os(macOS)
import AppKit

typealias MarkdownPlatformColor = NSColor
typealias MarkdownPlatformFont = NSFont
#elseif os(iOS)
import UIKit

typealias MarkdownPlatformColor = UIColor
typealias MarkdownPlatformFont = UIFont
#endif

extension MarkdownPlatformColor {
    static var defaultLabel: MarkdownPlatformColor {
        #if os(macOS)
        .labelColor
        #else
        .label
        #endif
    }
}

/// Stores one reusable theme colour and provides SwiftUI, native-editor, and CSS representations.
struct MarkdownSyntaxColor: Equatable {
    let hex: String

    private var components: (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let integer = Int(value, radix: 16) else {
            return nil
        }

        return (
            red: CGFloat((integer >> 16) & 0xFF) / 255.0,
            green: CGFloat((integer >> 8) & 0xFF) / 255.0,
            blue: CGFloat(integer & 0xFF) / 255.0
        )
    }

    var color: Color {
        guard let components else {
            return .primary
        }

        return Color(
            red: Double(components.red),
            green: Double(components.green),
            blue: Double(components.blue)
        )
    }

    var platformColor: MarkdownPlatformColor {
        guard let components else {
            return .defaultLabel
        }

        return MarkdownPlatformColor(
            red: components.red,
            green: components.green,
            blue: components.blue,
            alpha: 1
        )
    }
}

/// Contains every raw colour supplied by issue #12; missing light counterparts remain optional.
struct MarkdownPalette: Equatable {
    let red: MarkdownSyntaxColor
    let orange: MarkdownSyntaxColor
    let yellow: MarkdownSyntaxColor
    let warmNeutral: MarkdownSyntaxColor
    let green: MarkdownSyntaxColor
    let teal: MarkdownSyntaxColor
    let lightCyan: MarkdownSyntaxColor?
    let cyan: MarkdownSyntaxColor
    let lightBlue: MarkdownSyntaxColor
    let blue: MarkdownSyntaxColor
    let purple: MarkdownSyntaxColor
    let primaryText: MarkdownSyntaxColor
    let secondaryText: MarkdownSyntaxColor
    let tertiaryText: MarkdownSyntaxColor?
    let muted: MarkdownSyntaxColor
    let surface: MarkdownSyntaxColor
    let background: MarkdownSyntaxColor?

    var closestLightCyan: MarkdownSyntaxColor {
        lightCyan ?? cyan
    }

    var closestTertiaryText: MarkdownSyntaxColor {
        tertiaryText ?? muted
    }

    var closestBackground: MarkdownSyntaxColor {
        background ?? surface
    }

    static let dark = MarkdownPalette(
        red: MarkdownSyntaxColor(hex: "#f7768e"),
        orange: MarkdownSyntaxColor(hex: "#ff9e64"),
        yellow: MarkdownSyntaxColor(hex: "#e0af68"),
        warmNeutral: MarkdownSyntaxColor(hex: "#cfc9c2"),
        green: MarkdownSyntaxColor(hex: "#9ece6a"),
        teal: MarkdownSyntaxColor(hex: "#73dacb"),
        lightCyan: MarkdownSyntaxColor(hex: "#b4f9f8"),
        cyan: MarkdownSyntaxColor(hex: "#2ac3de"),
        lightBlue: MarkdownSyntaxColor(hex: "#7dcfff"),
        blue: MarkdownSyntaxColor(hex: "#7aa2f7"),
        purple: MarkdownSyntaxColor(hex: "#bb9af7"),
        primaryText: MarkdownSyntaxColor(hex: "#c0caf5"),
        secondaryText: MarkdownSyntaxColor(hex: "#a9b1d6"),
        tertiaryText: MarkdownSyntaxColor(hex: "#9aa5ce"),
        muted: MarkdownSyntaxColor(hex: "#565f89"),
        surface: MarkdownSyntaxColor(hex: "#414868"),
        background: MarkdownSyntaxColor(hex: "#1a1b26")
    )

    static let light = MarkdownPalette(
        red: MarkdownSyntaxColor(hex: "#8c4351"),
        orange: MarkdownSyntaxColor(hex: "#965027"),
        yellow: MarkdownSyntaxColor(hex: "#8f5e15"),
        warmNeutral: MarkdownSyntaxColor(hex: "#634f30"),
        green: MarkdownSyntaxColor(hex: "#385f0d"),
        teal: MarkdownSyntaxColor(hex: "#33635c"),
        lightCyan: nil,
        cyan: MarkdownSyntaxColor(hex: "#006c86"),
        lightBlue: MarkdownSyntaxColor(hex: "#0f4b6e"),
        blue: MarkdownSyntaxColor(hex: "#2959aa"),
        purple: MarkdownSyntaxColor(hex: "#5a3e8e"),
        primaryText: MarkdownSyntaxColor(hex: "#343b58"),
        secondaryText: MarkdownSyntaxColor(hex: "#40434f"),
        tertiaryText: nil,
        muted: MarkdownSyntaxColor(hex: "#6c6e75"),
        surface: MarkdownSyntaxColor(hex: "#e6e7ed"),
        background: nil
    )
}

/// Semantic editor colours derived from one central palette.
struct MarkdownEditorTheme: Equatable {
    let normalText: MarkdownSyntaxColor
    let markup: MarkdownSyntaxColor
    let headingPrimary: MarkdownSyntaxColor
    let headingSecondary: MarkdownSyntaxColor
    let bold: MarkdownSyntaxColor
    let italic: MarkdownSyntaxColor
    let strikethrough: MarkdownSyntaxColor
    let linkText: MarkdownSyntaxColor
    let linkDestination: MarkdownSyntaxColor
    let blockquote: MarkdownSyntaxColor
    let listMarker: MarkdownSyntaxColor
    let inlineCode: MarkdownSyntaxColor
    let codeFence: MarkdownSyntaxColor
    let codeLanguage: MarkdownSyntaxColor
    let horizontalRule: MarkdownSyntaxColor
    let specialCharacter: MarkdownSyntaxColor
    let tableHeader: MarkdownSyntaxColor
    let tableBody: MarkdownSyntaxColor
}

/// Calmer semantic colours used by rendered Markdown.
struct MarkdownPreviewTheme: Equatable {
    let body: MarkdownSyntaxColor
    let secondaryText: MarkdownSyntaxColor
    let headingPrimary: MarkdownSyntaxColor
    let headingSecondary: MarkdownSyntaxColor
    let headingTertiary: MarkdownSyntaxColor
    let bold: MarkdownSyntaxColor
    let italic: MarkdownSyntaxColor
    let strikethrough: MarkdownSyntaxColor
    let link: MarkdownSyntaxColor
    let blockquoteText: MarkdownSyntaxColor
    let blockquoteIndicator: MarkdownSyntaxColor
    let inlineCode: MarkdownSyntaxColor
    let inlineCodeBackground: MarkdownSyntaxColor
    let horizontalRule: MarkdownSyntaxColor
    let listMarker: MarkdownSyntaxColor
    let border: MarkdownSyntaxColor
}

/// Semantic programming-language token colours shared by native and WebKit rendering.
struct MarkdownCodeTheme: Equatable {
    let plain: MarkdownSyntaxColor
    let keyword: MarkdownSyntaxColor
    let type: MarkdownSyntaxColor
    let string: MarkdownSyntaxColor
    let number: MarkdownSyntaxColor
    let function: MarkdownSyntaxColor
    let property: MarkdownSyntaxColor
    let comment: MarkdownSyntaxColor
    let `operator`: MarkdownSyntaxColor
    let constant: MarkdownSyntaxColor
}

/// Unified Markdown theme selected from the current system appearance.
struct MarkdownTheme: Equatable {
    let palette: MarkdownPalette
    let editor: MarkdownEditorTheme
    let preview: MarkdownPreviewTheme
    let code: MarkdownCodeTheme

    static let dark = MarkdownTheme(palette: .dark, lightAppearance: false)
    static let light = MarkdownTheme(palette: .light, lightAppearance: true)

    private init(palette: MarkdownPalette, lightAppearance: Bool) {
        self.palette = palette
        editor = MarkdownEditorTheme(
            normalText: palette.primaryText,
            markup: palette.muted,
            headingPrimary: palette.blue,
            headingSecondary: palette.lightBlue,
            bold: palette.yellow,
            italic: palette.purple,
            strikethrough: palette.closestTertiaryText,
            linkText: palette.lightBlue,
            linkDestination: palette.cyan,
            blockquote: palette.green,
            listMarker: palette.red,
            inlineCode: palette.orange,
            codeFence: palette.muted,
            codeLanguage: palette.teal,
            horizontalRule: palette.surface,
            specialCharacter: palette.closestLightCyan,
            tableHeader: palette.blue,
            tableBody: palette.primaryText
        )
        preview = MarkdownPreviewTheme(
            body: palette.primaryText,
            secondaryText: palette.secondaryText,
            headingPrimary: palette.blue,
            headingSecondary: palette.lightBlue,
            headingTertiary: palette.secondaryText,
            bold: palette.yellow,
            italic: palette.purple,
            strikethrough: palette.closestTertiaryText,
            link: palette.lightBlue,
            blockquoteText: palette.green,
            blockquoteIndicator: lightAppearance ? palette.teal : palette.muted,
            inlineCode: palette.orange,
            inlineCodeBackground: palette.surface,
            horizontalRule: palette.surface,
            listMarker: palette.red,
            border: palette.surface
        )
        code = MarkdownCodeTheme(
            plain: palette.primaryText,
            keyword: palette.purple,
            type: palette.lightBlue,
            string: palette.green,
            number: palette.orange,
            function: palette.blue,
            property: palette.primaryText,
            comment: palette.muted,
            operator: palette.teal,
            constant: palette.red
        )
    }

    static func preferred(for colorScheme: ColorScheme) -> MarkdownTheme {
        colorScheme == .dark ? .dark : .light
    }

    // The exhaustive switch intentionally keeps every syntax role visibly mapped in one place.
    // swiftlint:disable:next cyclomatic_complexity
    func color(for role: MarkdownHighlightRole) -> MarkdownSyntaxColor {
        if let codeRole = role.codeRole {
            return codeColor(for: codeRole)
        }

        return switch role {
        case .headingMarker, .strongMarker, .emphasisMarker, .strikethroughMarker,
             .inlineCodeMarker, .quoteMarker, .linkMarker, .tableMarker, .tableDelimiter:
            editor.markup
        case let .headingText(level):
            level <= 3 ? editor.headingPrimary : editor.headingSecondary
        case .strongText:
            editor.bold
        case .emphasisText:
            editor.italic
        case .strikethroughText:
            editor.strikethrough
        case .inlineCodeText:
            editor.inlineCode
        case .codeFence:
            editor.codeFence
        case .codeLanguageIdentifier:
            editor.codeLanguage
        case .quoteText:
            editor.blockquote
        case .listMarker:
            editor.listMarker
        case .linkText:
            editor.linkText
        case .linkDestination:
            editor.linkDestination
        case .thematicBreak:
            editor.horizontalRule
        case .escapedCharacter:
            editor.specialCharacter
        case .tableHeader:
            editor.tableHeader
        case .tableBody:
            editor.tableBody
        case .codeComment, .codeKeyword, .codeString, .codeNumber, .codeType,
             .codeFunction, .codeOperator, .codeTag, .codeAttribute, .codeConstant:
            editor.markup
        }
    }

    func codeColor(for role: MarkdownCodeHighlightRole) -> MarkdownSyntaxColor {
        switch role {
        case .comment: code.comment
        case .keyword: code.keyword
        case .string: code.string
        case .number: code.number
        case .type, .tag: code.type
        case .function: code.function
        case .operator: code.operator
        case .attribute: code.property
        case .constant: code.constant
        }
    }

    /// Uses the preview bold role for hashtags while keeping their foreground readable.
    var previewHashtagColors: MarkdownTagColors {
        MarkdownTagColors(background: preview.bold, foreground: palette.closestBackground)
    }
}

/// Colours for hashtag capsules derived from the active Markdown theme.
struct MarkdownTagColors: Equatable {
    let background: MarkdownSyntaxColor
    let foreground: MarkdownSyntaxColor

    var backgroundColor: Color {
        background.color
    }

    var foregroundColor: Color {
        foreground.color
    }
}
