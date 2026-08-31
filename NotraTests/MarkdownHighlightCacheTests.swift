@testable import Notra
import Foundation
import Testing

@MainActor
/// Verifies that incremental syntax highlighting remains equivalent to a full parse.
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

    @Test func typingInLargeDocumentUsesSmallEditRange() {
        let markdown = largeMarkdown(lineCount: 2_000)
        var cache = MarkdownHighlightCache()
        cache.setText(markdown)

        let insertion = " edited"
        let location = (markdown as NSString).range(of: "Line 1200 with").location + "Line 1200".utf16.count
        let edited = (markdown as NSString).replacingCharacters(
            in: NSRange(location: location, length: 0),
            with: insertion
        )
        let changedRange = cache.updateText(
            edited,
            edit: MarkdownTextEdit(range: NSRange(location: location, length: 0), replacementUTF16Length: insertion.utf16.count)
        )

        #expect(changedRange?.count == 1)
        #expect(flattenedSpans(in: cache) == utf16Spans(in: edited))
    }

    @Test func insertingNewlineInLargeDocumentUsesSmallEditRange() {
        let markdown = largeMarkdown(lineCount: 2_000)
        var cache = MarkdownHighlightCache()
        cache.setText(markdown)

        let location = (markdown as NSString).range(of: "Line 20 with").location + "Line 20".utf16.count
        let edited = (markdown as NSString).replacingCharacters(
            in: NSRange(location: location, length: 0),
            with: "\n"
        )
        let changedRange = cache.updateText(
            edited,
            edit: MarkdownTextEdit(range: NSRange(location: location, length: 0), replacementUTF16Length: 1)
        )

        #expect((changedRange?.count ?? 0) <= 2)
        #expect(flattenedSpans(in: cache) == utf16Spans(in: edited))
    }

    @Test func editRangeStillRehighlightsFenceStateChanges() {
        let markdown = """
        ``swift
        let value = 1
        plain after
        """
        var cache = MarkdownHighlightCache()
        cache.setText(markdown)

        let edited = (markdown as NSString).replacingCharacters(
            in: NSRange(location: 0, length: 0),
            with: "`"
        )
        let changedRange = cache.updateText(
            edited,
            edit: MarkdownTextEdit(range: NSRange(location: 0, length: 0), replacementUTF16Length: 1)
        )

        #expect(changedRange == 0..<3)
        #expect(flattenedSpans(in: cache) == utf16Spans(in: edited))
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

    private func largeMarkdown(lineCount: Int) -> String {
        (0..<lineCount)
            .map { line in
                "Line \(line) with `code` and **bold** text"
            }
            .joined(separator: "\n")
    }
}
