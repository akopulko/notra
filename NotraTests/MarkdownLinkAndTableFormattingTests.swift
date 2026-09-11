import Foundation
@testable import Notra
import Testing

/// Covers link cursor placement and table formatting around selections and Unicode text.
struct MarkdownLinkAndTableFormattingTests {
    @Test func linkWithoutSelectionInEmptyDocumentPlacesCursorInsideLabel() {
        let text = ""
        let result = MarkdownFormatting.applyLinkResult(
            to: text,
            selection: text.startIndex ..< text.startIndex
        )

        #expect(result.text == "[](https://)")
        #expect(cursorOffset(in: result) == 1)
    }

    @Test func linkWithoutSelectionInMiddleOfTextPlacesCursorInsideInsertedLabel() {
        let text = "Hello world"
        let cursor = text.firstIndex(of: " ") ?? text.endIndex
        let result = MarkdownFormatting.applyLinkResult(to: text, selection: cursor ..< cursor)

        #expect(result.text == "Hello[](https://) world")
        #expect(cursorOffset(in: result) == 6)
    }

    @Test func linkWithSelectionUsesSelectionAsLabelAndPlacesCursorInURL() {
        let text = "Selected text"
        let result = MarkdownFormatting.applyLinkResult(
            to: text,
            selection: text.startIndex ..< text.endIndex
        )

        #expect(result.text == "[Selected text](https://)")
        #expect(cursorOffset(in: result) == 24)
    }

    @Test func linkWithUnicodeSelectionPreservesSelectedTextAndPlacesCursorInURL() {
        let text = "A 😀 note"
        let lowerBound = text.firstIndex(of: "😀") ?? text.startIndex
        let upperBound = text.firstIndex(of: "n") ?? text.endIndex
        let result = MarkdownFormatting.applyLinkResult(to: text, selection: lowerBound ..< upperBound)

        #expect(result.text == "A [😀 ](https://)note")
        #expect(cursorOffset(in: result) == 15)
    }

    @Test func legacyLinkCommandWithoutSelectionDoesNotInsertPlaceholder() {
        let markdown = MarkdownFormatting.apply(.link, to: "", selection: nil)

        #expect(markdown == "[](https://)")
    }

    @Test func imageAtBeginningOfDocumentUsesSpecAssetReference() {
        let text = ""
        let result = MarkdownFormatting.applyImageResult(
            to: text,
            selection: text.startIndex ..< text.startIndex,
            source: "assets/image.jpg"
        )

        #expect(result.text == "![](assets/image.jpg)\n")
        #expect(cursorOffset(in: result) == result.text.count)
    }

    @Test func imageAtCursorMidLineUsesBlockLineBreaks() {
        let text = "Some text"
        let cursor = text.firstIndex(of: " ") ?? text.endIndex
        let result = MarkdownFormatting.applyImageResult(
            to: text,
            selection: cursor ..< cursor,
            source: "assets/image.jpg"
        )

        #expect(result.text == "Some\n![](assets/image.jpg)\n text")
        #expect(cursorOffset(in: result) == "Some\n![](assets/image.jpg)\n".count)
    }

    @Test func imageSelectionBecomesAltText() {
        let text = "Selected text"
        let result = MarkdownFormatting.applyImageResult(
            to: text,
            selection: text.startIndex ..< text.endIndex,
            source: "assets/image.jpg"
        )

        #expect(result.text == "![Selected text](assets/image.jpg)\n")
        #expect(cursorOffset(in: result) == result.text.count)
    }

    @Test func imageUnicodeAltTextPreservesCursorOffset() {
        let text = "A 😀 note"
        let lowerBound = text.firstIndex(of: "😀") ?? text.startIndex
        let upperBound = text.index(after: lowerBound)
        let result = MarkdownFormatting.applyImageResult(
            to: text,
            selection: lowerBound ..< upperBound,
            source: "assets/image.jpg"
        )

        #expect(result.text == "A \n![😀](assets/image.jpg)\n note")
        #expect(cursorOffset(in: result) == "A \n![😀](assets/image.jpg)\n".count)
    }

    @Test func imageAtCursorAfterListMarkerStartsOnNextLine() {
        let text = "-"
        let result = MarkdownFormatting.applyImageResult(
            to: text,
            selection: text.endIndex ..< text.endIndex,
            source: "assets/paris-france.jpg"
        )

        #expect(result.text == "-\n![](assets/paris-france.jpg)\n")
        #expect(cursorOffset(in: result) == result.text.count)
    }

    @Test func imageMultilineSelectionCannotBreakImageSyntax() {
        let text = "Before\n-\nAfter"
        let selection = text.range(of: "\n-\n") ?? text.startIndex ..< text.startIndex
        let result = MarkdownFormatting.applyImageResult(
            to: text,
            selection: selection,
            source: "assets/image.jpg"
        )

        #expect(result.text == "Before\n![ - ](assets/image.jpg)\nAfter")
    }

    @Test func attachmentLinkAtCursorMidLineUsesBlockLineBreaks() {
        let text = "Some text"
        let cursor = text.firstIndex(of: " ") ?? text.endIndex
        let result = MarkdownFormatting.applyAttachmentLinkResult(
            to: text,
            selection: cursor ..< cursor,
            label: "report.pdf",
            source: "assets/report.pdf"
        )

        #expect(result.text == "Some\n[report.pdf](assets/report.pdf)\n text")
        #expect(cursorOffset(in: result) == "Some\n[report.pdf](assets/report.pdf)\n".count)
    }

    @Test func attachmentAtCursorAfterListMarkerStartsOnNextLine() {
        let text = "-"
        let result = MarkdownFormatting.applyAttachmentLinkResult(
            to: text,
            selection: text.endIndex ..< text.endIndex,
            label: "report.pdf",
            source: "assets/report.pdf"
        )

        #expect(result.text == "-\n[report.pdf](assets/report.pdf)\n")
        #expect(cursorOffset(in: result) == result.text.count)
    }

    @Test func tableAtBeginningOfDocumentPlacesCursorAfterTemplate() {
        let text = ""
        let result = MarkdownFormatting.applyTableResult(
            to: text,
            selection: text.startIndex ..< text.startIndex
        )

        #expect(result.text == tableTemplate)
        #expect(cursorOffset(in: result) == result.text.count)
    }

    @Test func tableAfterExistingTextStartsOnNextLine() {
        let text = "Some text"
        let result = MarkdownFormatting.applyTableResult(
            to: text,
            selection: text.endIndex ..< text.endIndex
        )

        #expect(result.text == "Some text\n\(tableTemplate)")
        #expect(cursorOffset(in: result) == result.text.count)
    }

    @Test func tableWhenCursorIsMidLineStartsOnNewLineAndKeepsTrailingText() {
        let text = "Some text"
        let cursor = text.firstIndex(of: " ") ?? text.endIndex
        let result = MarkdownFormatting.applyTableResult(to: text, selection: cursor ..< cursor)
        let tableEnd = result.text.range(of: "\n text")?.lowerBound ?? result.text.endIndex

        #expect(result.text == "Some\n\(tableTemplate)\n text")
        #expect(result.text.distance(from: result.text.startIndex, to: tableEnd) == cursorOffset(in: result))
    }

    private var tableTemplate: String {
        """
        | Header 1 | Header 2 |
        | --- | --- |
        |  |  |
        |  |  |
        """
    }

    private func cursorOffset(in result: MarkdownFormattingResult) -> Int {
        result.text.distance(from: result.text.startIndex, to: result.selection.lowerBound)
    }
}
