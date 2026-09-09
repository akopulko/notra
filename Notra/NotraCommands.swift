import Observation
import SwiftUI

/// Identifies a formatting action requested from the app's scene command menu.
enum NoteEditorCommand: Equatable {
    case heading(MarkdownHeadingLevel)
    case formatting(NoteFormattingCommand)
}

/// Carries repeated editor menu actions without losing identical consecutive requests.
struct NoteEditorCommandRequest: Equatable {
    let id: Int
    let command: NoteEditorCommand
}

/// Identifies the export presentation to perform for a selected note.
enum NoteExportAction: Equatable {
    case sharePDF
    case exportPDF
    case exportMarkdown
}

/// Carries repeated export actions without treating two identical commands as one update.
struct NoteExportRequest: Equatable {
    let id: Int
    let action: NoteExportAction
}

/// Tracks share presentation while a PDF is being prepared for the system share sheet.
enum NoteShareState {
    case idle
    case generating
    case failed
}

/// Publishes the active scene's commands without passing action closures through focus values.
@MainActor
@Observable
final class NotraCommandContext {
    let store: NotesStore
    var isEditing = false
    private(set) var editorCommandRequest: NoteEditorCommandRequest?
    /// Monotonic request that focuses the native editor after the preview-toggle command enters edit mode.
    private(set) var editorFocusRequestID = 0
    private(set) var newNoteRequestID = 0
    private(set) var attachmentRequestID = 0
    private(set) var exportRequest: NoteExportRequest?
    /// Presents the shortcuts reference for the active scene.
    var isKeyboardShortcutsPresented = false
    var shareState = NoteShareState.idle

    init(store: NotesStore) {
        self.store = store
    }

    var canCreateNote: Bool {
        !store.isChangingStorage
    }

    var canEditSelectedNote: Bool {
        store.hasSelection && isEditing && !store.isChangingStorage
    }

    var canExportSelectedNote: Bool {
        store.hasSelection && !isEditing && !store.isChangingStorage
    }

    func createNote() {
        guard canCreateNote else {
            return
        }

        newNoteRequestID += 1
    }

    func togglePreview() {
        guard store.hasSelection else {
            return
        }

        if isEditing {
            isEditing = false
        } else {
            editorFocusRequestID += 1
            isEditing = true
        }
    }

    func requestAttachment() {
        guard canEditSelectedNote else {
            return
        }

        attachmentRequestID += 1
    }

    func applyHeading(_ level: MarkdownHeadingLevel) {
        requestEditorCommand(.heading(level))
    }

    func applyFormatting(_ command: NoteFormattingCommand) {
        requestEditorCommand(.formatting(command))
    }

    func requestExport(_ action: NoteExportAction) {
        guard canExportSelectedNote else {
            return
        }

        let id = (exportRequest?.id ?? 0) + 1
        exportRequest = NoteExportRequest(id: id, action: action)
    }

    func showKeyboardShortcuts() {
        isKeyboardShortcutsPresented = true
    }

    private func requestEditorCommand(_ command: NoteEditorCommand) {
        guard canEditSelectedNote else {
            return
        }

        let id = (editorCommandRequest?.id ?? 0) + 1
        editorCommandRequest = NoteEditorCommandRequest(id: id, command: command)
    }
}

/// Adds standard menu commands on macOS and hardware-keyboard commands on iPadOS.
struct NotraCommands: Commands {
    @FocusedValue(NotraCommandContext.self) private var context

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") {
                context?.createNote()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(!(context?.canCreateNote ?? false))
        }

        CommandGroup(after: .newItem) {
            Divider()

            Button("Share") {
                context?.requestExport(.sharePDF)
            }
            .disabled(!(context?.canExportSelectedNote ?? false))

            Divider()

            Menu("Export…") {
                Button("PDF") {
                    context?.requestExport(.exportPDF)
                }
                .disabled(!(context?.canExportSelectedNote ?? false))

                Button("Markdown") {
                    context?.requestExport(.exportMarkdown)
                }
                .disabled(!(context?.canExportSelectedNote ?? false))
            }
        }

        CommandMenu("Format") {
            Menu("Header") {
                headingButton(.h1, shortcut: "1")
                headingButton(.h2, shortcut: "2")
                headingButton(.h3, shortcut: "3")
                headingButton(.h4, shortcut: "4")
                headingButton(.h5, shortcut: "5")
                headingButton(.h6, shortcut: "6")
            }

            Divider()

            formatButton(.unorderedList, shortcut: "8", modifiers: [.command, .shift])
            formatButton(.orderedList, shortcut: "7", modifiers: [.command, .shift])
            formatButton(.todo, shortcut: "9", modifiers: [.command, .shift])
            formatButton(.quote, shortcut: "u", modifiers: [.command, .shift])
            formatButton(.code, shortcut: "c", modifiers: [.command, .option])

            Divider()

            Menu("Font") {
                formatButton(.bold, shortcut: "b", modifiers: .command)
                formatButton(.italic, shortcut: "i", modifiers: .command)
                formatButton(.strikethrough, shortcut: "x", modifiers: [.command, .shift])
            }
        }

        CommandMenu("Insert") {
            Button("Attachment") {
                context?.requestAttachment()
            }
            .disabled(!(context?.canEditSelectedNote ?? false))

            formatButton(.table, shortcut: "t", modifiers: [.command, .option])
            formatButton(.link, shortcut: "k", modifiers: .command)
        }

        CommandGroup(before: .sidebar) {
            Button("Toggle Preview") {
                context?.togglePreview()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(context?.store.hasSelection != true)

            Divider()
        }

        SidebarCommands()

        CommandGroup(after: .sidebar) {
            Divider()

            Menu("Sort By") {
                sortFieldButton(.dateEdited)
                sortFieldButton(.dateCreated)

                Divider()

                sortDirectionButton(.latestFirst)
                sortDirectionButton(.oldestFirst)
            }
            .disabled(context == nil)
        }

        CommandGroup(after: .help) {
            Button("Notra Help") {}
            Button("Keyboard Shortcuts") {
                context?.showKeyboardShortcuts()
            }
            .keyboardShortcut("/", modifiers: .command)
        }
    }

    private func headingButton(_ level: MarkdownHeadingLevel, shortcut: KeyEquivalent) -> some View {
        Button(level.menuTitle) {
            context?.applyHeading(level)
        }
        .keyboardShortcut(shortcut, modifiers: [.command, .option])
        .disabled(!(context?.canEditSelectedNote ?? false))
    }

    private func formatButton(
        _ command: NoteFormattingCommand,
        shortcut: KeyEquivalent,
        modifiers: EventModifiers
    ) -> some View {
        Button(command.title) {
            context?.applyFormatting(command)
        }
        .keyboardShortcut(shortcut, modifiers: modifiers)
        .disabled(!(context?.canEditSelectedNote ?? false))
    }

    private func sortFieldButton(_ field: NoteSortField) -> some View {
        Button {
            context?.store.setSortField(field)
        } label: {
            if context?.store.sortPreference.field == field {
                Label(field.menuTitle, systemImage: "checkmark")
            } else {
                Text(field.menuTitle)
            }
        }
    }

    private func sortDirectionButton(_ direction: NoteSortDirection) -> some View {
        Button {
            context?.store.setSortDirection(direction)
        } label: {
            if context?.store.sortPreference.direction == direction {
                Label(direction.menuTitle, systemImage: "checkmark")
            } else {
                Text(direction.menuTitle)
            }
        }
    }
}
