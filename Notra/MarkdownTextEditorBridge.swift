import Foundation

final class MarkdownTextEditorBridge {
    var applyProgrammaticEdit: ((String, MarkdownEditorSelectionSnapshot) -> Void)?
    var focusEditor: (() -> Void)?
    var refreshHighlight: (() -> Void)?
    var performUndo: (() -> Void)?
    var performRedo: (() -> Void)?
    var refreshUndoRedoAvailability: (() -> Void)?
    var reportUndoRedoAvailability: ((EditorUndoRedoAvailability) -> Void)?
    var applyFormattingCommand: ((NoteFormattingCommand) -> Void)?
    var applyHeading: ((MarkdownHeadingLevel) -> Void)?
    var commitTagEntry: ((MarkdownEditorSelectionSnapshot) -> Bool)?
}

struct EditorUndoRedoAvailability: Equatable {
    var canUndo = false
    var canRedo = false

    static let disabled = EditorUndoRedoAvailability()
}
