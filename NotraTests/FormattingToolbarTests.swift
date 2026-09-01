@testable import Notra
import Testing

struct FormattingToolbarTests {
    @Test func keyboardAccessoryCommandsExcludeImageImport() {
        #expect(!NoteFormattingCommand.keyboardAccessoryCommands.contains(.image))
        #expect(NoteFormattingCommand.keyboardAccessoryCommands == [
            .hashtag,
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

    @Test func hashtagMetadataUsesExpectedTitleAndSymbol() {
        #expect(NoteFormattingCommand.hashtag.title == "Hashtag")
        #expect(NoteFormattingCommand.hashtag.systemImage == "number")
    }

    @Test func toolbarPlacesHashtagFirstAfterHeadingMenu() {
        #expect(NoteFormattingCommand.toolbarCommandGroups[0] == [.hashtag, .bold, .italic])
    }

    @Test func attachmentMenuMembershipRemainsUnchanged() {
        #expect(AttachmentKeyboardMenuItem.allCases == [.choosePhoto, .attachFile])
    }

    #if os(iOS)
    @Test func iOSEditMenuExcludesHashtagAndPreservesImageImport() {
        #expect(!NoteFormattingCommand.editorMenuCommands.contains(.hashtag))
        #expect(NoteFormattingCommand.editorMenuCommands.last == .image)
    }
    #else
    @Test func macOSEditorMenuIncludesHashtag() {
        #expect(NoteFormattingCommand.editorMenuCommands.contains(.hashtag))
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
