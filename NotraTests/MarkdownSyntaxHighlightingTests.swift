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
        - item with **bold** and _italic_
        > quote
        [link](https://example.com) `code`
        """

        let roles = MarkdownSyntaxHighlighter().spans(in: markdown).map(\.role)

        #expect(roles.contains(.headingMarker))
        #expect(roles.contains(.headingText))
        #expect(roles.contains(.listMarker))
        #expect(roles.contains(.emphasisMarker))
        #expect(roles.contains(.emphasisText))
        #expect(roles.contains(.quoteMarker))
        #expect(roles.contains(.linkText))
        #expect(roles.contains(.linkDestination))
        #expect(roles.contains(.inlineCode))
    }

    @Test func highlightsFencesAndRecognizedFenceContent() {
        let markdown = """
        ```swift
        let value = 1
        ```
        """

        let spans = MarkdownSyntaxHighlighter().spans(in: markdown)

        #expect(spans.filter { $0.role == .codeFence }.count == 2)
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

    @Test func darkAndLightThemesUseDistinctRoleColors() {
        #expect(MarkdownHighlightTheme.tokyoNight.heading.hex != MarkdownHighlightTheme.light.heading.hex)
        #expect(MarkdownHighlightTheme.tokyoNight.code.hex != MarkdownHighlightTheme.light.code.hex)
        #expect(MarkdownHighlightTheme.tokyoNight.table.hex != MarkdownHighlightTheme.light.table.hex)
        #expect(MarkdownHighlightTheme.preferred(for: .dark) == .tokyoNight)
        #expect(MarkdownHighlightTheme.preferred(for: .light) == .light)
    }

    @Test func tagColorsFollowThemeCodeColor() {
        #expect(MarkdownHighlightTheme.tokyoNight.tagColors(for: .dark).background == MarkdownHighlightTheme.tokyoNight.code)
        #expect(MarkdownHighlightTheme.light.tagColors(for: .light).background == MarkdownHighlightTheme.light.code)
        #expect(MarkdownHighlightTheme.tokyoNight.tagColors(for: .dark).foreground.hex == "#293F1A")
        #expect(MarkdownHighlightTheme.light.tagColors(for: .light).foreground.hex == "#FFFFFF")
        #expect(MarkdownTagColors.neutral.background.hex == "#6B7280")
        #expect(MarkdownTagColors.neutral.foreground.hex == "#D1D5DB")
    }

    @Test func noteListTitleColorFollowsThemeHeadingColor() {
        #expect(MarkdownHighlightTheme.tokyoNight.noteListTitleSyntaxColor == MarkdownHighlightTheme.tokyoNight.heading)
        #expect(MarkdownHighlightTheme.light.noteListTitleSyntaxColor == MarkdownHighlightTheme.light.heading)
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
