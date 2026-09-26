import Foundation
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
        #expect(String(localized: NoteStartContent.titleHeader.title) == "Title (H1)")
        #expect(NoteStartContent.titleHeader.initialMarkdown == "# ")
        #expect(String(localized: NoteStartContent.emptyNote.title) == "Empty Note")
        #expect(NoteStartContent.emptyNote.initialMarkdown.isEmpty)
    }
}
