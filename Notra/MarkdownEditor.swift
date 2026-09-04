import Foundation
import SwiftUI

/// Hosts the native text editor and translates toolbar requests into editor mutations.
struct MarkdownEditor: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppearanceSettingKey.editorFontName) private var editorFontName = AppearanceFont.defaultName
    @AppStorage(AppearanceSettingKey.editorFontSize) private var editorFontSize = AppearanceFont.defaultSize

    @Binding var text: String
    let applyFormattingCommand: (NoteFormattingCommand) -> Void
    let applyHeading: (MarkdownHeadingLevel) -> Void
    let requestAttachmentSelection: () -> Void
    let headingFormattingRequest: MarkdownHeadingFormattingRequest
    let hashtagFormattingRequest: Int
    let boldFormattingRequest: Int
    let italicFormattingRequest: Int
    let codeFormattingRequest: Int
    let linkFormattingRequest: Int
    let tableFormattingRequest: Int
    let imageFormattingRequest: MarkdownImageFormattingRequest
    let attachmentFormattingRequest: MarkdownAttachmentFormattingRequest
    let linePrefixFormattingRequest: MarkdownLinePrefixFormattingRequest
    let undoRequest: Int
    let redoRequest: Int
    let focusFirstLineRequest: Int
    let onUndoRedoAvailabilityChanged: (EditorUndoRedoAvailability) -> Void

    @State private var bridge = MarkdownTextEditorBridge()
    @State private var selectionStore = MarkdownEditorSelectionStore()

    var body: some View {
        MarkdownNativeTextEditor(
            text: $text,
            fontName: editorFontName,
            fontSize: editorFontSize,
            theme: MarkdownTheme.preferred(for: colorScheme),
            bridge: bridge,
            selectionStore: selectionStore
        )
        .accessibilityLabel("Note editor")
        .onChange(of: colorScheme) {
            bridge.refreshHighlight?()
        }
        .onChange(of: headingFormattingRequest) {
            applyHeadingFormatting()
        }
        .onChange(of: hashtagFormattingRequest) {
            applyHashtagFormatting()
        }
        .onChange(of: boldFormattingRequest) {
            applyBoldFormatting()
        }
        .onChange(of: italicFormattingRequest) {
            applyItalicFormatting()
        }
        .onChange(of: codeFormattingRequest) {
            applyCodeFormatting()
        }
        .onChange(of: linkFormattingRequest) {
            applyLinkFormatting()
        }
        .onChange(of: tableFormattingRequest) {
            applyTableFormatting()
        }
        .onChange(of: imageFormattingRequest) {
            applyImageFormatting()
        }
        .onChange(of: attachmentFormattingRequest) {
            applyAttachmentFormatting()
        }
        .onChange(of: linePrefixFormattingRequest) {
            applyLinePrefixFormatting()
        }
        .onChange(of: undoRequest) {
            bridge.performUndo?()
        }
        .onChange(of: redoRequest) {
            bridge.performRedo?()
        }
        .onChange(of: focusFirstLineRequest) {
            focusFirstLine()
        }
        .onAppear {
            bridge.applyFormattingCommand = applyFormattingCommand
            bridge.applyHeading = applyHeading
            bridge.requestAttachmentSelection = requestAttachmentSelection
            bridge.reportUndoRedoAvailability = onUndoRedoAvailabilityChanged
            bridge.refreshUndoRedoAvailability?()
            if focusFirstLineRequest > 0 {
                focusFirstLine()
            }
        }
        .onDisappear {
            onUndoRedoAvailabilityChanged(.disabled)
        }
    }
}

private extension MarkdownEditor {
    private func applyHeadingFormatting() {
        let currentText = text
        let selectedRange = formattingSelection(in: currentText)
        let result = MarkdownFormatting.applyHeadingResult(
            level: headingFormattingRequest.level,
            to: currentText,
            selection: selectedRange
        )
        applyFormattingResult(result, command: .heading, oldTextLength: currentText.count)
    }

    private func applyBoldFormatting() {
        applyInlineFormatting(command: .bold)
    }

    private func applyHashtagFormatting() {
        let currentText = text
        let selectedRange = formattingSelection(in: currentText)
        let result = MarkdownFormatting.applyHashtagResult(to: currentText, selection: selectedRange)
        applyFormattingResult(result, command: .hashtag, oldTextLength: currentText.count)
    }

    private func applyItalicFormatting() {
        applyInlineFormatting(command: .italic)
    }

    private func applyCodeFormatting() {
        applyInlineFormatting(command: .code)
    }

    private func applyLinkFormatting() {
        applyInlineFormatting(command: .link)
    }

    private func applyTableFormatting() {
        let currentText = text
        let selectedRange = formattingSelection(in: currentText)
        let result = MarkdownFormatting.applyTableResult(to: currentText, selection: selectedRange)
        applyFormattingResult(result, command: .table, oldTextLength: currentText.count)
    }

    private func applyImageFormatting() {
        guard !imageFormattingRequest.source.isEmpty else {
            return
        }

        let currentText = text
        let selectedRange = formattingSelection(in: currentText)
        AppLog.info(
            """
            Applying image markdown insertion; \
            requestID=\(imageFormattingRequest.id); source=\(imageFormattingRequest.source); \
            selection=\(rangeDescription(selectedRange, in: currentText))
            """
        )
        let result = MarkdownFormatting.applyImageResult(
            to: currentText,
            selection: selectedRange,
            source: imageFormattingRequest.source
        )
        applyFormattingResult(result, command: .image, oldTextLength: currentText.count)
    }

    private func applyAttachmentFormatting() {
        guard !attachmentFormattingRequest.source.isEmpty,
              !attachmentFormattingRequest.label.isEmpty
        else {
            return
        }

        let currentText = text
        let selectedRange = formattingSelection(in: currentText)
        AppLog.info(
            """
            Applying attachment markdown insertion; \
            requestID=\(attachmentFormattingRequest.id); source=\(attachmentFormattingRequest.source); \
            selection=\(rangeDescription(selectedRange, in: currentText))
            """
        )
        let result = MarkdownFormatting.applyAttachmentLinkResult(
            to: currentText,
            selection: selectedRange,
            label: attachmentFormattingRequest.label,
            source: attachmentFormattingRequest.source
        )
        applyFormattingResult(result, command: .link, oldTextLength: currentText.count)
    }

    private func applyLinePrefixFormatting() {
        let currentText = text
        let selectedRange = formattingSelection(in: currentText)

        let result: MarkdownFormattingResult
        switch linePrefixFormattingRequest.command {
        case .unorderedList:
            result = MarkdownFormatting.applyUnorderedListResult(to: currentText, selection: selectedRange)
        case .orderedList:
            result = MarkdownFormatting.applyOrderedListResult(to: currentText, selection: selectedRange)
        case .quote:
            result = MarkdownFormatting.applyQuoteResult(to: currentText, selection: selectedRange)
        case .todo:
            result = MarkdownFormatting.applyTodoResult(to: currentText, selection: selectedRange)
        case .bold, .italic, .heading, .hashtag, .code, .link, .table, .image:
            return
        }

        applyFormattingResult(
            result,
            command: linePrefixFormattingRequest.command,
            oldTextLength: currentText.count
        )
    }

    private func applyInlineFormatting(command: NoteFormattingCommand) {
        let currentText = text
        let selectedRange = formattingSelection(in: currentText)

        let result: MarkdownFormattingResult
        switch command {
        case .bold:
            result = MarkdownFormatting.applyBoldResult(to: currentText, selection: selectedRange)
        case .italic:
            result = MarkdownFormatting.applyItalicResult(to: currentText, selection: selectedRange)
        case .code:
            result = MarkdownFormatting.applyCodeResult(to: currentText, selection: selectedRange)
        case .link:
            result = MarkdownFormatting.applyLinkResult(to: currentText, selection: selectedRange)
        case .heading, .hashtag, .unorderedList, .orderedList, .quote, .todo, .table, .image:
            return
        }

        applyFormattingResult(result, command: command, oldTextLength: currentText.count)
    }

    private func applyFormattingResult(
        _ result: MarkdownFormattingResult,
        command: NoteFormattingCommand,
        oldTextLength: Int
    ) {
        AppLog.info(
            """
            \(command.logTitle) formatting applied; \
            oldLength=\(oldTextLength); newLength=\(result.text.count); \
            cursor=\(rangeDescription(result.selection, in: result.text))
            """
        )

        let resultSnapshot = snapshot(for: result.selection, in: result.text)
        selectionStore.snapshot = resultSnapshot
        selectionStore.lastNonEmptySnapshot = nil
        bridge.applyProgrammaticEdit?(result.text, resultSnapshot)
        text = result.text
        bridge.focusEditor?()
    }

    private func focusFirstLine() {
        let firstLineEndOffset = firstLineEndUTF16Offset(in: text)
        let firstLineSnapshot = MarkdownEditorSelectionSnapshot(
            lowerOffset: firstLineEndOffset,
            upperOffset: firstLineEndOffset
        )
        selectionStore.snapshot = firstLineSnapshot
        selectionStore.lastNonEmptySnapshot = nil
        bridge.applyProgrammaticEdit?(text, firstLineSnapshot)
        bridge.focusEditor?()
    }

    private func firstLineEndUTF16Offset(in text: String) -> Int {
        let newline = "\n".utf16.first!
        guard let newlineIndex = text.utf16.firstIndex(of: newline) else {
            return text.utf16.count
        }

        return text.utf16.distance(from: text.utf16.startIndex, to: newlineIndex)
    }

    private func formattingSelection(in plainText: String) -> Range<String.Index> {
        let currentSnapshot = selectionStore.snapshot

        if currentSnapshot.isEmpty, let lastNonEmptySelectionSnapshot = selectionStore.lastNonEmptySnapshot {
            return range(from: lastNonEmptySelectionSnapshot, in: plainText)
        }

        return range(from: currentSnapshot, in: plainText)
    }

    private func snapshot(
        for range: Range<String.Index>,
        in text: String
    ) -> MarkdownEditorSelectionSnapshot {
        MarkdownEditorSelectionSnapshot(
            lowerOffset: range.lowerBound.utf16Offset(in: text),
            upperOffset: range.upperBound.utf16Offset(in: text)
        )
    }

    private func range(
        from snapshot: MarkdownEditorSelectionSnapshot,
        in text: String
    ) -> Range<String.Index> {
        let lowerOffset = min(max(snapshot.lowerOffset, 0), text.utf16.count)
        let upperOffset = min(max(snapshot.upperOffset, lowerOffset), text.utf16.count)
        let lowerBound = stringIndex(atUTF16Offset: lowerOffset, in: text)
        let upperBound = stringIndex(atUTF16Offset: upperOffset, in: text)

        return lowerBound..<upperBound
    }

    private func stringIndex(atUTF16Offset offset: Int, in text: String) -> String.Index {
        let clampedOffset = min(max(offset, 0), text.utf16.count)
        let utf16Index = text.utf16.index(text.utf16.startIndex, offsetBy: clampedOffset)
        return String.Index(utf16Index, within: text) ?? text.endIndex
    }

    private func rangeDescription(
        _ range: Range<String.Index>,
        in text: String
    ) -> String {
        let lowerOffset = range.lowerBound.utf16Offset(in: text)
        let upperOffset = range.upperBound.utf16Offset(in: text)
        let lowerCoordinate = coordinate(for: range.lowerBound, in: text)
        let upperCoordinate = coordinate(for: range.upperBound, in: text)

        return """
        offsets=\(lowerOffset)..<\(upperOffset); \
        lower=line \(lowerCoordinate.line), column \(lowerCoordinate.column); \
        upper=line \(upperCoordinate.line), column \(upperCoordinate.column); \
        isEmpty=\(range.isEmpty); textLength=\(text.count)
        """
    }

    private func snapshotDescription(
        _ snapshot: MarkdownEditorSelectionSnapshot,
        in text: String
    ) -> String {
        rangeDescription(range(from: snapshot, in: text), in: text)
    }

    private func optionalSnapshotDescription(
        _ snapshot: MarkdownEditorSelectionSnapshot?,
        in text: String
    ) -> String {
        guard let snapshot else {
            return "nil"
        }

        return snapshotDescription(snapshot, in: text)
    }

    private func coordinate(for index: String.Index, in text: String) -> (line: Int, column: Int) {
        let prefix = text[..<index]
        let line = prefix.reduce(1) { partialResult, character in
            character == "\n" ? partialResult + 1 : partialResult
        }
        let lineStart = prefix.lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let column = text.distance(from: lineStart, to: index) + 1

        return (line, column)
    }
}

/// Identifies a requested heading-level formatting operation.
struct MarkdownHeadingFormattingRequest: Equatable {
    let id: Int
    let level: MarkdownHeadingLevel
}

/// Identifies a list or quote operation that prefixes the selected lines.
struct MarkdownLinePrefixFormattingRequest: Equatable {
    let id: Int
    let command: NoteFormattingCommand
}

/// Carries the source for an image link insertion request.
struct MarkdownImageFormattingRequest: Equatable {
    let id: Int
    let source: String
}

/// Carries the source and label for an attachment link insertion request.
struct MarkdownAttachmentFormattingRequest: Equatable {
    let id: Int
    let source: String
    let label: String
}

private extension NoteFormattingCommand {
    var logTitle: String {
        switch self {
        case .bold:
            "Bold"
        case .italic:
            "Italic"
        case .heading:
            "Heading"
        case .hashtag:
            "Hashtag"
        case .unorderedList:
            "Unordered list"
        case .orderedList:
            "Ordered list"
        case .quote:
            "Quote"
        case .todo:
            "Todo"
        case .code:
            "Code"
        case .link:
            "Link"
        case .table:
            "Table"
        case .image:
            "Image"
        }
    }
}
