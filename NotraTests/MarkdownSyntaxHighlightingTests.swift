@testable import Notra
import SwiftUI
import Testing

@MainActor
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

    @Test func highlightsFencesWithoutHighlightingFenceContent() {
        let markdown = """
        ```swift
        let value = 1
        ```
        """

        let spans = MarkdownSyntaxHighlighter().spans(in: markdown)

        #expect(spans.filter { $0.role == .codeFence }.count == 2)
        #expect(spans.allSatisfy { String(markdown[$0.range]) != "let" })
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
