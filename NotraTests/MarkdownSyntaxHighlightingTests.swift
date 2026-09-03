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

    @Test func lightPaletteMatchesIssueSpecificationAndUsesClosestFallbacks() {
        let palette = MarkdownPalette.light

        #expect([
            palette.red.hex, palette.orange.hex, palette.yellow.hex, palette.warmNeutral.hex,
            palette.green.hex, palette.teal.hex, palette.cyan.hex, palette.lightBlue.hex,
            palette.blue.hex, palette.purple.hex, palette.primaryText.hex, palette.secondaryText.hex,
            palette.muted.hex, palette.surface.hex,
        ] == [
            "#8c4351", "#965027", "#8f5e15", "#634f30", "#385f0d", "#33635c",
            "#006c86", "#0f4b6e", "#2959aa", "#5a3e8e", "#343b58", "#40434f",
            "#6c6e75", "#e6e7ed",
        ])
        #expect(palette.closestLightCyan == palette.cyan)
        #expect(palette.closestTertiaryText == palette.muted)
        #expect(palette.closestBackground == palette.surface)
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

    @Test func tagColorsFollowSharedPalette() {
        #expect(MarkdownTheme.dark.tagColors(for: .dark).background == MarkdownPalette.dark.green)
        #expect(MarkdownTheme.light.tagColors(for: .light).background == MarkdownPalette.light.green)
        #expect(MarkdownTheme.dark.tagColors(for: .dark).foreground == MarkdownPalette.dark.background)
        #expect(MarkdownTheme.light.tagColors(for: .light).foreground == MarkdownPalette.light.surface)
        #expect(MarkdownTagColors.neutral.background.hex == "#6B7280")
        #expect(MarkdownTagColors.neutral.foreground.hex == "#D1D5DB")
    }

    @Test func noteListTitleColorFollowsThemeHeadingColor() {
        #expect(MarkdownTheme.dark.noteListTitleColor == MarkdownTheme.dark.preview.headingPrimary.color)
        #expect(MarkdownTheme.light.noteListTitleColor == MarkdownTheme.light.preview.headingPrimary.color)
    }

    @Test func noteListDateColorFollowsThemeLinkColor() {
        #expect(MarkdownTheme.dark.noteListDateColor == MarkdownTheme.dark.preview.link.color)
        #expect(MarkdownTheme.light.noteListDateColor == MarkdownTheme.light.preview.link.color)
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
