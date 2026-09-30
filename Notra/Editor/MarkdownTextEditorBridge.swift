import Foundation

/// Shares native text-view handles and command closures between SwiftUI and editor controls.
final class MarkdownTextEditorBridge {
    /// Applies a formatted string and restores the selection returned by the formatter.
    var applyProgrammaticEdit: ((String, MarkdownEditorSelectionSnapshot) -> Void)?
    /// Requests focus from the platform-native text view.
    var focusEditor: (() -> Void)?
    /// Asks the coordinator to recolor the current text without changing its contents.
    var refreshHighlight: (() -> Void)?
    /// Applies a command selected from the native menu or accessory toolbar.
    var applyFormattingCommand: ((NoteFormattingCommand) -> Void)?
    /// Applies a selected heading level from the native menu or accessory toolbar.
    var applyHeading: ((MarkdownHeadingLevel) -> Void)?
    /// Requests the parent SwiftUI view to present the platform attachment picker.
    var requestAttachmentSelection: (() -> Void)?
}
