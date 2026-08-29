@testable import Notra
import Foundation
import Testing

/// Exercises selection-preserving Markdown transformations for editor commands.
struct MarkdownFormattingTests {
    @Test func appliesEveryHeadingLevel() {
        for level in MarkdownHeadingLevel.allCases {
            let markdown = MarkdownFormatting.applyHeading(
                level: level,
                to: "Heading",
                selection: nil
            )

            #expect(markdown == "\(level.markdownPrefix)Heading")
        }
    }

    @Test func replacesExistingHeadingLevel() {
        let markdown = MarkdownFormatting.applyHeading(level: .h3, to: "# Title", selection: nil)

        #expect(markdown == "### Title")
    }

    @Test func appliesHeadingAtStartOfLineContainingCursor() {
        let markdown = "Hello world"
        let cursor = markdown.firstIndex(of: " ") ?? markdown.endIndex

        let result = MarkdownFormatting.applyHeadingResult(
            level: .h2,
            to: markdown,
            selection: cursor ..< cursor
        )

        #expect(result.text == "## Hello world")
        #expect(cursorOffset(in: result) == 3)
    }

    @Test func appliesHeadingOnlyToSelectionStartLine() {
        let markdown = "One\n## Two\nThree"
        let selection = markdown.startIndex ..< markdown.endIndex

        let result = MarkdownFormatting.applyHeadingResult(
            level: .h4,
            to: markdown,
            selection: selection
        )

        #expect(result.text == "#### One\n## Two\nThree")
        #expect(cursorOffset(in: result) == 8)
    }

    @Test func appliesHeadingAtBeginningOfDocument() {
        let markdown = "Title"

        let result = MarkdownFormatting.applyHeadingResult(
            level: .h1,
            to: markdown,
            selection: markdown.startIndex ..< markdown.startIndex
        )

        #expect(result.text == "# Title")
        #expect(cursorOffset(in: result) == 2)
    }

    @Test func appliesHeadingAtEndOfDocument() {
        let markdown = "First\nTitle"

        let result = MarkdownFormatting.applyHeadingResult(
            level: .h3,
            to: markdown,
            selection: markdown.endIndex ..< markdown.endIndex
        )

        #expect(result.text == "First\n### Title")
        #expect(cursorOffset(in: result) == 10)
    }

    @Test func headingWithUnicodeLinePreservesTextAndCursorOffset() {
        let markdown = "A 😀 note"
        let cursor = markdown.firstIndex(of: "n") ?? markdown.endIndex

        let result = MarkdownFormatting.applyHeadingResult(
            level: .h2,
            to: markdown,
            selection: cursor ..< cursor
        )

        #expect(result.text == "## A 😀 note")
        #expect(cursorOffset(in: result) == 3)
    }

    @Test func legacyHeadingCommandAppliesH1() {
        let markdown = MarkdownFormatting.apply(.heading, to: "Title", selection: nil)

        #expect(markdown == "# Title")
    }

    @Test func existingInlineCommandsStillWork() {
        let text = "value"
        let markdown = MarkdownFormatting.apply(
            .bold,
            to: text,
            selection: text.startIndex ..< text.endIndex
        )

        #expect(markdown == "**value**")
    }

    @Test func boldWithoutSelectionInEmptyDocumentPlacesCursorInsideMarkup() {
        let text = ""
        let result = MarkdownFormatting.applyBoldResult(
            to: text,
            selection: text.startIndex ..< text.startIndex
        )

        #expect(result.text == "****")
        #expect(cursorOffset(in: result) == 2)
    }

    @Test func boldWithoutSelectionInMiddleOfTextPlacesCursorInsideInsertedMarkup() {
        let text = "Hello world"
        let cursor = text.firstIndex(of: " ") ?? text.endIndex
        let result = MarkdownFormatting.applyBoldResult(to: text, selection: cursor ..< cursor)

        #expect(result.text == "Hello**** world")
        #expect(cursorOffset(in: result) == 7)
    }

    @Test func boldWithSelectionPlacesCursorAfterClosingMarkup() {
        let text = "Selected text"
        let result = MarkdownFormatting.applyBoldResult(
            to: text,
            selection: text.startIndex ..< text.endIndex
        )

        #expect(result.text == "**Selected text**")
        #expect(cursorOffset(in: result) == 17)
    }

    @Test func boldWithUnicodeSelectionPreservesSelectedText() {
        let text = "A 😀 note"
        let lowerBound = text.firstIndex(of: "😀") ?? text.startIndex
        let upperBound = text.firstIndex(of: "n") ?? text.endIndex
        let result = MarkdownFormatting.applyBoldResult(to: text, selection: lowerBound ..< upperBound)

        #expect(result.text == "A **😀 **note")
        #expect(cursorOffset(in: result) == 8)
    }

    @Test func italicWithoutSelectionInEmptyDocumentPlacesCursorInsideMarkup() {
        let text = ""
        let result = MarkdownFormatting.applyItalicResult(
            to: text,
            selection: text.startIndex ..< text.startIndex
        )

        #expect(result.text == "__")
        #expect(cursorOffset(in: result) == 1)
    }

    @Test func italicWithoutSelectionInMiddleOfTextPlacesCursorInsideInsertedMarkup() {
        let text = "Hello world"
        let cursor = text.firstIndex(of: " ") ?? text.endIndex
        let result = MarkdownFormatting.applyItalicResult(to: text, selection: cursor ..< cursor)

        #expect(result.text == "Hello__ world")
        #expect(cursorOffset(in: result) == 6)
    }

    @Test func italicWithSelectionPlacesCursorAfterClosingMarkup() {
        let text = "Selected text"
        let result = MarkdownFormatting.applyItalicResult(
            to: text,
            selection: text.startIndex ..< text.endIndex
        )

        #expect(result.text == "_Selected text_")
        #expect(cursorOffset(in: result) == 15)
    }

    @Test func italicWithUnicodeSelectionPreservesSelectedText() {
        let text = "A 😀 note"
        let lowerBound = text.firstIndex(of: "😀") ?? text.startIndex
        let upperBound = text.firstIndex(of: "n") ?? text.endIndex
        let result = MarkdownFormatting.applyItalicResult(to: text, selection: lowerBound ..< upperBound)

        #expect(result.text == "A _😀 _note")
        #expect(cursorOffset(in: result) == 6)
    }

    @Test func codeWithoutSelectionInEmptyDocumentPlacesCursorInsideMarkup() {
        let text = ""
        let result = MarkdownFormatting.applyCodeResult(
            to: text,
            selection: text.startIndex ..< text.startIndex
        )

        #expect(result.text == "``")
        #expect(cursorOffset(in: result) == 1)
    }

    @Test func codeWithoutSelectionInMiddleOfTextPlacesCursorInsideInsertedMarkup() {
        let text = "Hello world"
        let cursor = text.firstIndex(of: " ") ?? text.endIndex
        let result = MarkdownFormatting.applyCodeResult(to: text, selection: cursor ..< cursor)

        #expect(result.text == "Hello`` world")
        #expect(cursorOffset(in: result) == 6)
    }

    @Test func codeWithSelectionPlacesCursorAfterClosingMarkup() {
        let text = "Selected text"
        let result = MarkdownFormatting.applyCodeResult(
            to: text,
            selection: text.startIndex ..< text.endIndex
        )

        #expect(result.text == "`Selected text`")
        #expect(cursorOffset(in: result) == 15)
    }

    @Test func codeWithUnicodeSelectionPreservesSelectedText() {
        let text = "A 😀 note"
        let lowerBound = text.firstIndex(of: "😀") ?? text.startIndex
        let upperBound = text.firstIndex(of: "n") ?? text.endIndex
        let result = MarkdownFormatting.applyCodeResult(to: text, selection: lowerBound ..< upperBound)

        #expect(result.text == "A `😀 `note")
        #expect(cursorOffset(in: result) == 6)
    }

    @Test func legacyCodeCommandWithoutSelectionDoesNotInsertPlaceholder() {
        let markdown = MarkdownFormatting.apply(.code, to: "", selection: nil)

        #expect(markdown == "``")
    }

    @Test func unorderedListWithoutSelectionPrefixesContainingLine() {
        let text = "Hello world"
        let cursor = text.firstIndex(of: " ") ?? text.endIndex
        let result = MarkdownFormatting.applyUnorderedListResult(to: text, selection: cursor ..< cursor)

        #expect(result.text == "- Hello world")
        #expect(cursorOffset(in: result) == 7)
    }

    @Test func unorderedListWithoutSelectionOnEmptyLineInsertsMarkerAtCursor() {
        let text = ""
        let result = MarkdownFormatting.applyUnorderedListResult(
            to: text,
            selection: text.startIndex ..< text.startIndex
        )

        #expect(result.text == "- ")
        #expect(cursorOffset(in: result) == 2)
    }

    @Test func orderedListWithoutSelectionOnEmptyLineInsertsMarkerAtCursor() {
        let text = ""
        let result = MarkdownFormatting.applyOrderedListResult(
            to: text,
            selection: text.startIndex ..< text.startIndex
        )

        #expect(result.text == "1. ")
        #expect(cursorOffset(in: result) == 3)
    }

    @Test func orderedListWithoutSelectionPrefixesContainingLine() {
        let text = "Hello world"
        let cursor = text.firstIndex(of: " ") ?? text.endIndex
        let result = MarkdownFormatting.applyOrderedListResult(to: text, selection: cursor ..< cursor)

        #expect(result.text == "1. Hello world")
        #expect(cursorOffset(in: result) == 8)
    }

    @Test func unorderedListWithSingleSelectedLinePrefixesLine() {
        let text = "Apple"
        let result = MarkdownFormatting.applyUnorderedListResult(
            to: text,
            selection: text.startIndex ..< text.endIndex
        )

        #expect(result.text == "- Apple")
        #expect(cursorOffset(in: result) == 7)
    }

    @Test func unorderedListWithMultiLineSelectionPrefixesEveryLine() {
        let text = "Apple\nBanana\nOrange"
        let result = MarkdownFormatting.applyUnorderedListResult(
            to: text,
            selection: text.startIndex ..< text.endIndex
        )

        #expect(result.text == "- Apple\n- Banana\n- Orange")
        #expect(cursorOffset(in: result) == 25)
    }

    @Test func orderedListWithMultiLineSelectionUsesSequentialNumbers() {
        let text = "Apple\nBanana\nOrange"
        let result = MarkdownFormatting.applyOrderedListResult(
            to: text,
            selection: text.startIndex ..< text.endIndex
        )

        #expect(result.text == "1. Apple\n2. Banana\n3. Orange")
        #expect(cursorOffset(in: result) == 28)
    }

    @Test func unorderedListWithPartialLineSelectionPrefixesWholeLine() {
        let text = "Intro\nApple pie\nOutro"
        let lowerBound = text.range(of: "pie")?.lowerBound ?? text.startIndex
        let upperBound = text.range(of: "pie")?.upperBound ?? text.endIndex
        let result = MarkdownFormatting.applyUnorderedListResult(to: text, selection: lowerBound ..< upperBound)

        #expect(result.text == "Intro\n- Apple pie\nOutro")
        #expect(cursorOffset(in: result) == 17)
    }

    @Test func unorderedListWithSelectionEndingAtNextLineStartDoesNotPrefixNextLine() {
        let text = "Apple\nBanana\nOrange"
        let upperBound = text.range(of: "Orange")?.lowerBound ?? text.endIndex
        let result = MarkdownFormatting.applyUnorderedListResult(
            to: text,
            selection: text.startIndex ..< upperBound
        )

        #expect(result.text == "- Apple\n- Banana\nOrange")
        #expect(cursorOffset(in: result) == 16)
    }

    @Test func unorderedListWithSelectedEmptyMiddleLinePrefixesEmptyLine() {
        let text = "Apple\n\nBanana"
        let result = MarkdownFormatting.applyUnorderedListResult(
            to: text,
            selection: text.startIndex ..< text.endIndex
        )

        #expect(result.text == "- Apple\n- \n- Banana")
        #expect(cursorOffset(in: result) == 19)
    }

    @Test func unorderedListWithUnicodeSelectionPreservesCursorOffset() {
        let text = "😀\nNote"
        let result = MarkdownFormatting.applyUnorderedListResult(
            to: text,
            selection: text.startIndex ..< text.endIndex
        )

        #expect(result.text == "- 😀\n- Note")
        #expect(cursorOffset(in: result) == 10)
    }

    @Test func quoteWithoutSelectionPrefixesContainingLine() {
        let text = "Hello world"
        let cursor = text.firstIndex(of: " ") ?? text.endIndex
        let result = MarkdownFormatting.applyQuoteResult(to: text, selection: cursor ..< cursor)

        #expect(result.text == "> Hello world")
        #expect(cursorOffset(in: result) == 7)
    }

    @Test func quoteWithoutSelectionOnEmptyLineInsertsMarkerAtCursor() {
        let text = ""
        let result = MarkdownFormatting.applyQuoteResult(
            to: text,
            selection: text.startIndex ..< text.startIndex
        )

        #expect(result.text == "> ")
        #expect(cursorOffset(in: result) == 2)
    }

    @Test func quoteWithSingleSelectedLinePrefixesLine() {
        let text = "Apple"
        let result = MarkdownFormatting.applyQuoteResult(
            to: text,
            selection: text.startIndex ..< text.endIndex
        )

        #expect(result.text == "> Apple")
        #expect(cursorOffset(in: result) == 7)
    }

    @Test func quoteWithMultiLineSelectionPrefixesEveryLine() {
        let text = "Apple\nBanana\nOrange"
        let result = MarkdownFormatting.applyQuoteResult(
            to: text,
            selection: text.startIndex ..< text.endIndex
        )

        #expect(result.text == "> Apple\n> Banana\n> Orange")
        #expect(cursorOffset(in: result) == 25)
    }

    @Test func quoteWithPartialLineSelectionPrefixesWholeLine() {
        let text = "Intro\nApple pie\nOutro"
        let lowerBound = text.range(of: "pie")?.lowerBound ?? text.startIndex
        let upperBound = text.range(of: "pie")?.upperBound ?? text.endIndex
        let result = MarkdownFormatting.applyQuoteResult(to: text, selection: lowerBound ..< upperBound)

        #expect(result.text == "Intro\n> Apple pie\nOutro")
        #expect(cursorOffset(in: result) == 17)
    }

    @Test func quoteWithSelectionEndingAtNextLineStartDoesNotPrefixNextLine() {
        let text = "Apple\nBanana\nOrange"
        let upperBound = text.range(of: "Orange")?.lowerBound ?? text.endIndex
        let result = MarkdownFormatting.applyQuoteResult(
            to: text,
            selection: text.startIndex ..< upperBound
        )

        #expect(result.text == "> Apple\n> Banana\nOrange")
        #expect(cursorOffset(in: result) == 16)
    }

    @Test func todoWithoutSelectionPrefixesContainingLine() {
        let text = "Hello world"
        let cursor = text.firstIndex(of: " ") ?? text.endIndex
        let result = MarkdownFormatting.applyTodoResult(to: text, selection: cursor ..< cursor)

        #expect(result.text == "- [ ] Hello world")
        #expect(cursorOffset(in: result) == 11)
    }

    @Test func todoWithoutSelectionOnEmptyLineInsertsMarkerAtCursor() {
        let text = ""
        let result = MarkdownFormatting.applyTodoResult(
            to: text,
            selection: text.startIndex ..< text.startIndex
        )

        #expect(result.text == "- [ ] ")
        #expect(cursorOffset(in: result) == 6)
    }

    @Test func todoWithSingleSelectedLinePrefixesLine() {
        let text = "Apple"
        let result = MarkdownFormatting.applyTodoResult(
            to: text,
            selection: text.startIndex ..< text.endIndex
        )

        #expect(result.text == "- [ ] Apple")
        #expect(cursorOffset(in: result) == 11)
    }

    @Test func todoWithMultiLineSelectionPrefixesEveryLine() {
        let text = "Apple\nBanana\nOrange"
        let result = MarkdownFormatting.applyTodoResult(
            to: text,
            selection: text.startIndex ..< text.endIndex
        )

        #expect(result.text == "- [ ] Apple\n- [ ] Banana\n- [ ] Orange")
        #expect(cursorOffset(in: result) == 37)
    }

    @Test func todoWithPartialLineSelectionPrefixesWholeLine() {
        let text = "Intro\nApple pie\nOutro"
        let lowerBound = text.range(of: "pie")?.lowerBound ?? text.startIndex
        let upperBound = text.range(of: "pie")?.upperBound ?? text.endIndex
        let result = MarkdownFormatting.applyTodoResult(to: text, selection: lowerBound ..< upperBound)

        #expect(result.text == "Intro\n- [ ] Apple pie\nOutro")
        #expect(cursorOffset(in: result) == 21)
    }

    @Test func todoWithSelectionEndingAtNextLineStartDoesNotPrefixNextLine() {
        let text = "Apple\nBanana\nOrange"
        let upperBound = text.range(of: "Orange")?.lowerBound ?? text.endIndex
        let result = MarkdownFormatting.applyTodoResult(
            to: text,
            selection: text.startIndex ..< upperBound
        )

        #expect(result.text == "- [ ] Apple\n- [ ] Banana\nOrange")
        #expect(cursorOffset(in: result) == 24)
    }

    @Test func todoWithUnicodeSelectionPreservesCursorOffset() {
        let text = "😀\nNote"
        let result = MarkdownFormatting.applyTodoResult(
            to: text,
            selection: text.startIndex ..< text.endIndex
        )

        #expect(result.text == "- [ ] 😀\n- [ ] Note")
        #expect(cursorOffset(in: result) == 18)
    }

    @Test func insertsEmptyTableWithHeader() {
        let markdown = MarkdownFormatting.apply(.table, to: "", selection: nil)

        #expect(markdown == """
        | Header 1 | Header 2 |
        | --- | --- |
        |  |  |
        |  |  |
        """)
    }

    @Test func separatesInsertedTableFromExistingMarkdown() {
        let markdown = MarkdownFormatting.apply(.table, to: "# Title", selection: nil)

        #expect(markdown == """
        # Title
        | Header 1 | Header 2 |
        | --- | --- |
        |  |  |
        |  |  |
        """)
    }

    private func cursorOffset(in result: MarkdownFormattingResult) -> Int {
        result.text.distance(from: result.text.startIndex, to: result.selection.lowerBound)
    }
}
