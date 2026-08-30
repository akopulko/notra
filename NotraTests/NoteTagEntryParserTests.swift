import Foundation
@testable import Notra
import Testing

/// Protects standalone tag recognition from headings, prose, links, and fenced code.
struct NoteTagEntryParserTests {
    @Test func commitsStandaloneTagLine() throws {
        let text = "Before\n#SwiftUI\nAfter"
        let cursor = text.utf16Offset(of: "#SwiftUI") + "#SwiftUI".utf16.count
        let entry = try #require(NoteTagEntryParser.entry(
            in: text,
            selection: MarkdownEditorSelectionSnapshot(lowerOffset: cursor, upperOffset: cursor)
        ))

        #expect(entry.tag.name == "SwiftUI")
        #expect(entry.result.text == "Before\nAfter")
        #expect(entry.result.selection.lowerBound.utf16Offset(in: entry.result.text) == "Before\n".utf16.count)
    }

    @Test func ignoresMarkdownHeading() {
        #expect(entryTagName(in: "# Heading") == nil)
        #expect(entryTagName(in: "##") == nil)
    }

    @Test func ignoresSentenceHashtagAndPunctuation() {
        #expect(entryTagName(in: "Read #swift") == nil)
        #expect(entryTagName(in: "#swift.") == nil)
    }

    @Test func ignoresInlineCodeAndLinks() {
        #expect(entryTagName(in: "`#swift`") == nil)
        #expect(entryTagName(in: "[#swift](https://example.com)") == nil)
    }

    @Test func ignoresTagInsideFencedCodeBlock() {
        let text = "```\n#swift\n```"
        let cursor = "```\n#swift".utf16.count

        #expect(NoteTagEntryParser.entry(
            in: text,
            selection: MarkdownEditorSelectionSnapshot(lowerOffset: cursor, upperOffset: cursor)
        ) == nil)
    }

    @Test func acceptsUnicodeLettersNumbersHyphenAndUnderscore() {
        #expect(entryTagName(in: "#café-研究_26") == "café-研究_26")
    }

    private func entryTagName(in line: String) -> String? {
        NoteTagEntryParser.entry(
            in: line,
            selection: MarkdownEditorSelectionSnapshot(
                lowerOffset: line.utf16.count,
                upperOffset: line.utf16.count
            )
        )?.tag.name
    }
}

private extension String {
    func utf16Offset(of substring: String) -> Int {
        guard let range = range(of: substring) else {
            return 0
        }
        return range.lowerBound.utf16Offset(in: self)
    }
}
