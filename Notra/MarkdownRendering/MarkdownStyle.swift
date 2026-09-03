import SwiftUI

/// Defines typography, colors, spacing, and code-theme choices for Markdown output.
struct MarkdownStyle: Equatable {
    let bodyFont: Font
    let previewFontName: String
    let headingScales: [CGFloat]
    let textColor: Color
    let secondaryTextColor: Color
    let headingColor: Color
    let linkColor: Color
    let markerColor: Color
    let borderColor: Color
    let dividerColor: Color
    let quoteAccentColor: Color
    let codeTextColor: Color
    let codeSyntaxTheme: MarkdownTheme?
    let codeBlockFont: Font
    let inlineCodeFont: Font
    let blockSpacing: CGFloat
    let paragraphSpacing: CGFloat
    let listItemParagraphSpacing: CGFloat
    let listIndent: CGFloat
    let listMarkerWidth: CGFloat
    let tableCellPadding: CGFloat

    static func notra(
        previewFontName: String,
        theme: MarkdownTheme? = nil,
        renderMode: MarkdownRenderMode = .preview
    ) -> MarkdownStyle {
        let isPDF = renderMode == .pdf
        let appliedTheme = isPDF ? nil : theme
        let linkColor = appliedTheme?.preview.link.color ?? Color(red: 44 / 255, green: 101 / 255, blue: 207 / 255)
        let markerColor = appliedTheme?.preview.listMarker.color ?? (isPDF ? Color.gray : Color.secondary)
        let borderColor = appliedTheme?.preview.border.color ??
            (isPDF ? Color.gray.opacity(0.5) : Color.secondary.opacity(0.25))

        return MarkdownStyle(
            bodyFont: AppearanceFont.bodyFont(named: previewFontName),
            previewFontName: previewFontName,
            headingScales: [2, 1.5, 1.25, 1, 0.875, 0.85],
            textColor: appliedTheme?.preview.body.color ?? (isPDF ? .black : .primary),
            secondaryTextColor: appliedTheme?.preview.secondaryText.color ?? (isPDF ? .gray : .secondary),
            headingColor: appliedTheme?.preview.headingPrimary.color ?? (isPDF ? .black : .primary),
            linkColor: linkColor,
            markerColor: markerColor,
            borderColor: borderColor,
            dividerColor: appliedTheme?.preview.horizontalRule.color ?? markerColor.opacity(0.2),
            quoteAccentColor: appliedTheme?.preview.blockquoteIndicator.color ?? borderColor,
            codeTextColor: appliedTheme?.preview.inlineCode.color ?? (isPDF ? .black : .primary),
            codeSyntaxTheme: appliedTheme,
            codeBlockFont: .system(.body, design: .monospaced),
            inlineCodeFont: .system(.callout, design: .monospaced),
            blockSpacing: 0,
            paragraphSpacing: 16,
            listItemParagraphSpacing: 4,
            listIndent: 24,
            listMarkerWidth: 26,
            tableCellPadding: 8
        )
    }

    func headingFont(level: Int) -> Font {
        let index = min(max(level, 1), headingScales.count) - 1
        let size = CGFloat(AppearanceFont.defaultSize) * headingScales[index]

        guard !previewFontName.isEmpty else {
            return .system(size: size, weight: .semibold)
        }

        return .custom(previewFontName, size: size, relativeTo: .title).weight(.semibold)
    }

    var codeBlockBaseTextColor: Color {
        codeSyntaxTheme == nil ? codeTextColor : textColor
    }
}

extension EnvironmentValues {
    @Entry var markdownStyle: MarkdownStyle = .notra(previewFontName: AppearanceFont.defaultName)
}

extension EnvironmentValues {
    @Entry var secondaryBackgroundFill: BackgroundFill = .regular
}

/// Represents the background fill used by Markdown views and export surfaces.
enum BackgroundFill {
    case regular
    case thin
    case printable
    case clear

    @ViewBuilder
    var view: some View {
        switch self {
        case .regular:
            Rectangle().fill(.regularMaterial)
        case .thin:
            Rectangle().fill(.thinMaterial)
        case .printable:
            Rectangle().fill(Color(red: 0.94, green: 0.94, blue: 0.94))
        case .clear:
            Color.clear
        }
    }
}
