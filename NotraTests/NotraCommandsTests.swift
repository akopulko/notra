@testable import Notra
import Foundation
import Testing

#if os(macOS)
import AppKit
import SwiftUI
#endif

@MainActor
struct NotraCommandsTests {
    #if os(macOS)
    @Test func editorFocusRequestTransfersFirstResponderAfterWindowAttachment() async {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let sidebar = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 480))
        window.contentView?.addSubview(sidebar)
        #expect(window.makeFirstResponder(sidebar))

        let editor = MarkdownNativeTextEditor(
            text: .constant("Note"), fontName: AppearanceFont.defaultName,
            fontSize: AppearanceFont.defaultSize, theme: .light,
            bridge: MarkdownTextEditorBridge(), selectionStore: MarkdownEditorSelectionStore(),
            focusEditorRequest: 1
        )
        let coordinator = editor.makeCoordinator()
        // Deliver the command before mounting, matching the preview-to-editor transition.
        coordinator.update(scrollView: coordinator.scrollView)
        #expect(window.firstResponder === sidebar)
        window.contentView?.addSubview(coordinator.scrollView)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(window.firstResponder === coordinator.textView)
        (window.firstResponder as? NSTextView)?.insertText("typed", replacementRange: NSRange(location: 0, length: 0))
        #expect(coordinator.textView.string == "typedNote")
        #expect(sidebar.string.isEmpty)
    }
    #endif

    @Test func editorCommandsRequireAnEditingSelection() async throws {
        let rootURL = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = NotesStore(repository: TextBundleNoteRepository(rootURL: rootURL))
        await store.loadNotes()
        await store.createNote()

        let context = NotraCommandContext(store: store)
        context.applyFormatting(.bold)
        #expect(context.editorCommandRequest == nil)

        context.isEditing = true
        context.applyFormatting(.bold)
        #expect(context.editorCommandRequest?.command == .formatting(.bold))
        #expect(context.editorCommandRequest?.id == 1)

        context.applyFormatting(.bold)
        #expect(context.editorCommandRequest?.id == 2)
    }

    @Test func previewToggleRequestsEditorFocusOnlyWhenEnteringEditMode() async throws {
        let rootURL = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = NotesStore(repository: TextBundleNoteRepository(rootURL: rootURL))
        await store.loadNotes()
        await store.createNote()

        let context = NotraCommandContext(store: store)
        context.togglePreview()
        #expect(context.isEditing)
        #expect(context.editorFocusRequestID == 1)

        context.togglePreview()
        #expect(!context.isEditing)
        #expect(context.editorFocusRequestID == 1)
    }
}
