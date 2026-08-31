@testable import Notra
import Testing

struct FormattingToolbarTests {
    @Test func keyboardAccessoryCommandsExcludeImageImport() {
        #expect(!NoteFormattingCommand.keyboardAccessoryCommands.contains(.image))
        #expect(NoteFormattingCommand.keyboardAccessoryCommands == [
            .bold,
            .italic,
            .unorderedList,
            .orderedList,
            .todo,
            .quote,
            .link,
            .table,
            .code
        ])
    }

    @Test func attachmentKeyboardMenuItemsExposeTitlesAndIcons() {
        #expect(AttachmentKeyboardMenuItem.allCases == [.choosePhoto, .attachFile])
        #expect(AttachmentKeyboardMenuItem.choosePhoto.title == "Choose Photo")
        #expect(AttachmentKeyboardMenuItem.choosePhoto.systemImage == "photo")
        #expect(AttachmentKeyboardMenuItem.attachFile.title == "Attach File")
        #expect(AttachmentKeyboardMenuItem.attachFile.systemImage == "doc")
    }
}
