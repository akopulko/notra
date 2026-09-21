@testable import Notra
import SwiftUI
import Testing

@MainActor
/// Protects syntax-role detection for Markdown constructs and fenced code languages.
struct MarkdownSyntaxHighlightingTests {
    @Test func plainTextHasNoHighlightSpans() {
        let spans = MarkdownSyntaxHighlighter().spans(in: "plain text")

        #expect(spans.isEmpty)
    }

    @Test func unmatchedLinkOpenersDoNotPreventLaterValidLinkHighlighting() {
        let markdown = "[[[valid](https://example.com)"
        let spans = MarkdownSyntaxHighlighter().spans(in: markdown)

        #expect(spans.contains { $0.role == .linkText && String(markdown[$0.range]) == "valid" })
        #expect(spans.contains { $0.role == .linkDestination && String(markdown[$0.range]) == "https://example.com" })
    }

    @Test func highlightsCommonMarkdownRoles() {
        let markdown = """
        # Heading
        - item with **bold**, _italic_, ~~removed~~, and \\*escaped\\*
        > quote
        [link](https://example.com) `code`
        """

        let roles = MarkdownSyntaxHighlighter().spans(in: markdown).map(\.role)

        #expect(roles.contains(.headingMarker))
        #expect(roles.contains(.headingText(level: 1)))
        #expect(roles.contains(.listMarker))
        #expect(roles.contains(.strongMarker))
        #expect(roles.contains(.strongText))
        #expect(roles.contains(.emphasisMarker))
        #expect(roles.contains(.emphasisText))
        #expect(roles.contains(.strikethroughMarker))
        #expect(roles.contains(.strikethroughText))
        #expect(roles.contains(.quoteMarker))
        #expect(roles.contains(.quoteText))
        #expect(roles.contains(.linkText))
        #expect(roles.contains(.linkDestination))
        #expect(roles.contains(.inlineCodeMarker))
        #expect(roles.contains(.inlineCodeText))
        #expect(roles.contains(.escapedCharacter))
    }

    @Test func highlightsFencesAndRecognizedFenceContent() {
        let markdown = """
        ```swift
        let value = 1
        ```
        """

        let spans = MarkdownSyntaxHighlighter().spans(in: markdown)

        #expect(spans.filter { $0.role == .codeFence }.count == 2)
        #expect(spans.contains { $0.role == .codeLanguageIdentifier && String(markdown[$0.range]) == "swift" })
        #expect(spans.contains { $0.role == .codeKeyword && String(markdown[$0.range]) == "let" })
    }

    @Test func highlightsSupportedLanguageFenceContent() {
        let markdown = """
        ```swift
        // A comment
        let answer: Int = 42
        print(\"Notra\")
        ```
        """

        let roles = MarkdownSyntaxHighlighter().spans(in: markdown).map(\.role)

        #expect(roles.contains(.codeComment))
        #expect(roles.contains(.codeKeyword))
        #expect(roles.contains(.codeType))
        #expect(roles.contains(.codeNumber))
        #expect(roles.contains(.codeFunction))
        #expect(roles.contains(.codeString))
    }

    @Test func highlightsKnownConstantsSeparatelyFromNumbers() {
        let code = "let enabled = true; let count = 42"
        let spans = MarkdownCodeSyntaxHighlighter().spans(in: code, language: .swift)

        #expect(spans.contains { $0.role == .constant && String(code[$0.range]) == "true" })
        #expect(spans.contains { $0.role == .number && String(code[$0.range]) == "42" })
    }

    @Test func recognizesSupportedFenceLanguageAliases() {
        let supportedTags = [
            "swift", "python", "py", "javascript", "js", "jsx", "typescript", "ts", "tsx", "json",
            "html", "htm", "css", "bash", "sh", "zsh", "shell", "sql", "yaml", "yml", "c", "cpp",
            "cxx", "cc", "csharp", "cs", "java", "go", "rust", "rs", "kotlin", "kt", "ruby", "rb",
            "php", "xml", "markdown", "md",
        ]

        for tag in supportedTags {
            #expect(MarkdownCodeLanguage(fenceTag: tag) != nil)
        }
        #expect(MarkdownCodeLanguage(fenceTag: "unknown") == nil)
    }

    @Test func leavesUnsupportedFenceContentUnhighlighted() {
        let markdown = """
        ```unknown
        let answer = 42
        ```
        """

        let roles = MarkdownSyntaxHighlighter().spans(in: markdown).map(\.role)

        #expect(!roles.contains(.codeKeyword))
        #expect(!roles.contains(.codeNumber))
    }

    @Test func malformedMarkdownDoesNotCreateInlineSpans() {
        let markdown = "This is **unfinished and [not a link](missing"

        let roles = MarkdownSyntaxHighlighter().spans(in: markdown).map(\.role)

        #expect(!roles.contains(.emphasisText))
        #expect(!roles.contains(.linkDestination))
    }

    @Test func darkPaletteMatchesIssueSpecification() {
        let palette = MarkdownPalette.dark

        #expect([
            palette.red.hex, palette.orange.hex, palette.yellow.hex, palette.warmNeutral.hex,
            palette.green.hex, palette.teal.hex, palette.lightCyan?.hex, palette.cyan.hex,
            palette.lightBlue.hex, palette.blue.hex, palette.purple.hex, palette.primaryText.hex,
            palette.secondaryText.hex, palette.tertiaryText?.hex, palette.muted.hex,
            palette.surface.hex, palette.background?.hex,
        ] == [
            "#f7768e", "#ff9e64", "#e0af68", "#cfc9c2", "#9ece6a", "#73dacb",
            "#b4f9f8", "#2ac3de", "#7dcfff", "#7aa2f7", "#bb9af7", "#c0caf5",
            "#a9b1d6", "#9aa5ce", "#565f89", "#414868", "#1a1b26",
        ])
    }

    @Test func lightPaletteMatchesCurrentSpecification() {
        let palette = MarkdownPalette.light

        #expect([
            palette.red.hex, palette.orange.hex, palette.yellow.hex, palette.warmNeutral.hex,
            palette.green.hex, palette.teal.hex, palette.lightCyan?.hex, palette.cyan.hex,
            palette.lightBlue.hex, palette.blue.hex, palette.purple.hex, palette.primaryText.hex,
            palette.secondaryText.hex, palette.tertiaryText?.hex, palette.muted.hex,
            palette.surface.hex, palette.background?.hex,
        ] == [
            "#b4637a", "#ea9d34", "#d9a441", "#cecacd", "#56949f", "#56949f",
            "#9ccfd8", "#6e9faf", "#6e9faf", "#286983", "#907aa9", "#575279",
            "#797593", "#9893a5", "#9893a5", "#f2e9e1", "#faf4ed",
        ])
        #expect(palette.closestLightCyan.hex == "#9ccfd8")
        #expect(palette.closestTertiaryText.hex == "#9893a5")
        #expect(palette.closestBackground.hex == "#faf4ed")
    }

    @Test func semanticMappingsFollowEditorPreviewAndCodeRoles() {
        let theme = MarkdownTheme.dark

        #expect(theme.color(for: .headingText(level: 1)) == theme.palette.blue)
        #expect(theme.color(for: .headingText(level: 4)) == theme.palette.lightBlue)
        #expect(theme.color(for: .strongText) == theme.palette.yellow)
        #expect(theme.color(for: .emphasisText) == theme.palette.purple)
        #expect(theme.color(for: .strikethroughText) == theme.palette.tertiaryText)
        #expect(theme.color(for: .linkDestination) == theme.palette.cyan)
        #expect(theme.color(for: .quoteText) == theme.palette.green)
        #expect(theme.color(for: .listMarker) == theme.palette.red)
        #expect(theme.codeColor(for: .constant) == theme.palette.red)
        #expect(theme.codeColor(for: .attribute) == theme.palette.primaryText)
        #expect(MarkdownTheme.preferred(for: .dark) == .dark)
        #expect(MarkdownTheme.preferred(for: .light) == .light)
    }

    @Test func previewHashtagColorsFollowBoldThemeRole() {
        #expect(MarkdownTheme.dark.previewHashtagColors.background == MarkdownTheme.dark.preview.bold)
        #expect(MarkdownTheme.light.previewHashtagColors.background == MarkdownTheme.light.preview.bold)
        #expect(MarkdownTheme.dark.previewHashtagColors.foreground == MarkdownTheme.dark.palette.closestBackground)
        #expect(MarkdownTheme.light.previewHashtagColors.foreground == MarkdownTheme.light.palette.closestBackground)
    }

    @Test func highlightsTableHeaderDelimiterAndBodyRows() {
        let markdown = """
        | Name | Type |
        | --- | --- |
        | Markdown | Renderer |
        """

        let spans = MarkdownSyntaxHighlighter().spans(in: markdown)
        let roles = spans.map(\.role)

        #expect(roles.filter { $0 == .tableMarker }.count >= 6)
        #expect(roles.filter { $0 == .tableHeader }.count == 2)
        #expect(roles.filter { $0 == .tableDelimiter }.count == 1)
        #expect(roles.filter { $0 == .tableBody }.count == 2)

        let header = spans.first { $0.role == .tableHeader }
        #expect(String(markdown[header!.range]) == "Name")
    }

    @Test func tableInsideFenceIsNotHighlighted() {
        let markdown = """
        ```
        | Not a table |
        ```
        """

        let roles = MarkdownSyntaxHighlighter().spans(in: markdown).map(\.role)

        #expect(!roles.contains(.tableMarker))
        #expect(!roles.contains(.tableHeader))
        #expect(!roles.contains(.tableBody))
    }

    @Test func tableRowWithoutDelimiterIsBodyNotHeader() {
        let markdown = """
        | Markdown | Renderer |
        """

        let roles = MarkdownSyntaxHighlighter().spans(in: markdown).map(\.role)

        #expect(!roles.contains(.tableHeader))
        #expect(roles.filter { $0 == .tableBody }.count == 2)
    }

    @Test func escapedPipeIsNotTreatedAsColumnMarker() {
        let markdown = """
        | a \\| b | c |
        | --- | --- |
        """

        let spans = MarkdownSyntaxHighlighter().spans(in: markdown)
        let roles = spans.map(\.role)

        #expect(roles.filter { $0 == .tableMarker }.count == 3)
        #expect(roles.filter { $0 == .tableHeader }.count == 2)
        #expect(roles.filter { $0 == .tableBody }.count == 0)
        #expect(roles.filter { $0 == .tableDelimiter }.count == 1)
    }

    @Test func alignmentDelimiterRowIsRecognized() {
        let markdown = """
        | Left | Right |
        |:-----|------:|
        | Alpha | Beta |
        """

        let roles = MarkdownSyntaxHighlighter().spans(in: markdown).map(\.role)

        #expect(roles.filter { $0 == .tableDelimiter }.count == 1)
        #expect(roles.filter { $0 == .tableHeader }.count == 2)
        #expect(roles.filter { $0 == .tableBody }.count == 2)
    }
}
