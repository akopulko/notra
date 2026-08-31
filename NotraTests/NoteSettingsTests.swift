@testable import Notra
import Testing

struct NoteSettingsTests {
    @Test func defaultStartContentUsesTitleHeader() {
        #expect(NoteStartContent.defaultValue == .titleHeader)
        #expect(NoteStartContent.defaultValue.initialMarkdown == "# ")
    }

    @Test func resolvesUnknownStartContentToDefault() {
        #expect(NoteStartContent.resolved(rawValue: "unknown") == .titleHeader)
    }

    @Test func exposesMenuTitlesAndInitialMarkdown() {
        #expect(NoteStartContent.titleHeader.title == "Title Header (#H1)")
        #expect(NoteStartContent.titleHeader.initialMarkdown == "# ")
        #expect(NoteStartContent.emptyNote.title == "Empty Note")
        #expect(NoteStartContent.emptyNote.initialMarkdown.isEmpty)
    }
}
