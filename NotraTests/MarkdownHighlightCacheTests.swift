@testable import Notra
import Foundation
import Testing

@MainActor
struct MarkdownHighlightCacheTests {
    private let sampleMarkdown = """
    # Heading
    - item with **bold** and _italic_
    > quote with `code` and [link](https://example.com)
    | Name | Type |
    | --- | --- |
    | Markdown | Renderer |
    ```swift
    let value = 1
    ```
    - after fence
    """

    @Test func initialParseMatchesFullSpans() {
        var cache = MarkdownHighlightCache()
        cache.setText(sampleMarkdown)

        #expect(cache.text == sampleMarkdown)
        #expect(flattenedSpans(in: cache) == utf16Spans(in: sampleMarkdown))
    }

    @Test func typingInMiddleOfLineKeepsSpansConsistent() {
        let edited = sampleMarkdown.replacingOccurrences(
            of: "with **bold**",
            with: "with **extra bold**"
        )

        #expect(edited != sampleMarkdown)
        expectConsistentCache(afterEditingTo: edited)
    }

    @Test func insertingNewlineSplitsLine() {
        let edited = sampleMarkdown.replacingOccurrences(
            of: "item with **bold**",
            with: "item with\n**bold**"
        )

        expectConsistentCache(afterEditingTo: edited)
    }

    @Test func removingNewlineMergesLines() {
        let edited = sampleMarkdown.replacingOccurrences(
            of: "- item with **bold** and _italic_\n> quote",
            with: "- item with **bold** and _italic_ > quote"
        )

        expectConsistentCache(afterEditingTo: edited)
    }

    @Test func openingFenceRehighlightsFollowingLines() {
        let edited = sampleMarkdown.replacingOccurrences(
            of: "let value = 1\n```",
            with: "let value = 1\nlet other = 2\n```"
        )

        expectConsistentCache(afterEditingTo: edited)
    }

    @Test func editingInsideFenceKeepsFenceContentUnhighlighted() {
        let edited = sampleMarkdown.replacingOccurrences(
            of: "let value = 1",
            with: "let value = 1 // edited"
        )

        expectConsistentCache(afterEditingTo: edited)
    }

    @Test func addingFenceMarkerTogglesFollowingLines() {
        let edited = sampleMarkdown.replacingOccurrences(
            of: "```swift\nlet value = 1\n```",
            with: "```swift\nlet value = 1"
        )

        expectConsistentCache(afterEditingTo: edited)
    }

    @Test func clearingTextEmptiesCache() {
        var cache = MarkdownHighlightCache()
        cache.setText(sampleMarkdown)
        cache.updateText("")

        #expect(cache.isEmpty)
        #expect(cache.lines.isEmpty)
        #expect(cache.text.isEmpty)
    }

    @Test func editingTableCellKeepsSpansConsistent() {
        let edited = sampleMarkdown.replacingOccurrences(
            of: "| Markdown | Renderer |",
            with: "| Markdown | Highlighting |"
        )

        expectConsistentCache(afterEditingTo: edited)
    }

    @Test func insertingDelimiterRehighlightsHeaderRow() {
        let edited = sampleMarkdown.replacingOccurrences(
            of: "- item with **bold** and _italic_\n> quote",
            with: "- item with **bold** and _italic_\n| New Header |\n| --- |"
        )

        expectConsistentCache(afterEditingTo: edited)
    }

    @Test func removingDelimiterRehighlightsPreviousRow() {
        let edited = sampleMarkdown.replacingOccurrences(
            of: "| Name | Type |\n| --- | --- |",
            with: "| Name | Type |"
        )

        expectConsistentCache(afterEditingTo: edited)
    }

    private func expectConsistentCache(afterEditingTo edited: String) {
        var cache = MarkdownHighlightCache()
        cache.setText(sampleMarkdown)
        let changedRange = cache.updateText(edited)

        #expect(cache.text == edited)
        #expect(changedRange != nil)
        #expect(flattenedSpans(in: cache) == utf16Spans(in: edited))
    }

    private func flattenedSpans(in cache: MarkdownHighlightCache) -> [MarkdownUTF16Span] {
        cache.lines.flatMap(\.spans)
    }

    private func utf16Spans(in markdown: String) -> [MarkdownUTF16Span] {
        MarkdownSyntaxHighlighter().spans(in: markdown).map { span in
            MarkdownUTF16Span(
                role: span.role,
                lower: span.range.lowerBound.utf16Offset(in: markdown),
                upper: span.range.upperBound.utf16Offset(in: markdown)
            )
        }
    }
}
