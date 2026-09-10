@testable import Notra
import Testing

struct FormattingToolbarTests {
    @Test func keyboardAccessoryCommandsExcludeImageImport() {
        #expect(!NoteFormattingCommand.keyboardAccessoryCommands.contains(.image))
        #expect(NoteFormattingCommand.keyboardAccessoryCommands == [
            .bold,
            .italic,
            .strikethrough,
            .unorderedList,
            .orderedList,
            .todo,
            .quote,
            .link,
            .table,
            .code
        ])
    }

    @Test func toolbarPlacesInlineStylesAfterHeadingMenu() {
        #expect(NoteFormattingCommand.toolbarCommandGroups[0] == [.bold, .italic, .strikethrough])
    }

    @Test func attachmentMenuMembershipRemainsUnchanged() {
        #expect(AttachmentKeyboardMenuItem.allCases == [.choosePhoto, .attachFile])
    }

    #if os(iOS)
    @Test func iOSEditMenuPreservesImageImport() {
        #expect(NoteFormattingCommand.editorMenuCommands.last == .image)
    }
    #else
    @Test func macOSEditorMenuMatchesToolbarCommands() {
        #expect(NoteFormattingCommand.editorMenuCommands == NoteFormattingCommand.keyboardAccessoryCommands)
    }
    #endif

    @Test func attachmentKeyboardMenuItemsExposeTitlesAndIcons() {
        #expect(AttachmentKeyboardMenuItem.allCases == [.choosePhoto, .attachFile])
        #expect(AttachmentKeyboardMenuItem.choosePhoto.title == "Choose Photo")
        #expect(AttachmentKeyboardMenuItem.choosePhoto.systemImage == "photo")
        #expect(AttachmentKeyboardMenuItem.attachFile.title == "Attach File")
        #expect(AttachmentKeyboardMenuItem.attachFile.systemImage == "doc")
    }
}
