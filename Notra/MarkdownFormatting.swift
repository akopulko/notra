import Foundation

/// Returns formatted Markdown together with the selection that should remain active afterward.
struct MarkdownFormattingResult: Equatable {
    let text: String
    let selection: Range<String.Index>
}

/// Implements selection-aware Markdown transformations without depending on a text-view framework.
enum MarkdownFormatting {
    /// Applies a toolbar command and returns only text for callers that do not own selection state.
    static func apply(_ command: NoteFormattingCommand, to text: String, selection: Range<String.Index>?) -> String {
        let selectedRange = selection ?? text.endIndex..<text.endIndex

        switch command {
        case .bold:
            return applyBoldResult(to: text, selection: selectedRange).text
        case .italic:
            return applyItalicResult(to: text, selection: selectedRange).text
        case .strikethrough:
            return applyStrikethroughResult(to: text, selection: selectedRange).text
        case .heading:
            return applyHeading(level: .h1, to: text, selection: selection)
        case .unorderedList:
            return applyUnorderedListResult(to: text, selection: selectedRange).text
        case .orderedList:
            return applyOrderedListResult(to: text, selection: selectedRange).text
        case .quote:
            return applyQuoteResult(to: text, selection: selectedRange).text
        case .todo:
            return applyTodoResult(to: text, selection: selectedRange).text
        case .code:
            return applyCodeResult(to: text, selection: selectedRange).text
        case .link:
            return applyLinkResult(to: text, selection: selectedRange).text
        case .table:
            return applyTableResult(to: text, selection: selectedRange).text
        case .image:
            return text
        }
    }

    /// Wraps the selection in strong-emphasis markers, or inserts an empty pair at the cursor.
    static func applyBoldResult(to text: String, selection: Range<String.Index>) -> MarkdownFormattingResult {
        applyWrappedResult(to: text, selection: selection, prefix: "**", suffix: "**")
    }

    /// Wraps the selection in underscore emphasis markers while preserving the resulting selection.
    static func applyItalicResult(to text: String, selection: Range<String.Index>) -> MarkdownFormattingResult {
        applyWrappedResult(to: text, selection: selection, prefix: "_", suffix: "_")
    }

    /// Wraps the selection in strikethrough markers while preserving the resulting selection.
    static func applyStrikethroughResult(to text: String, selection: Range<String.Index>) -> MarkdownFormattingResult {
        applyWrappedResult(to: text, selection: selection, prefix: "~~", suffix: "~~")
    }

    /// Applies inline code to one line, or a fenced code block to a multiline selection.
    static func applyCodeResult(to text: String, selection: Range<String.Index>) -> MarkdownFormattingResult {
        guard text[selection].contains("\n") else {
            return applyWrappedResult(to: text, selection: selection, prefix: "`", suffix: "`")
        }

        let lineRange = expandedSelectedLineRange(in: text, for: selection)
        let replacement = "```\n\(text[lineRange])\n```"

        return resultReplacingLineRange(lineRange, in: text, with: replacement)
    }

    /// Inserts a Markdown link and places the cursor in the label or URL editing position.
    static func applyLinkResult(to text: String, selection: Range<String.Index>) -> MarkdownFormattingResult {
        let selectedText = String(text[selection])
        let replacement = "[\(selectedText)](https://)"
        var result = text

        result.replaceSubrange(selection, with: replacement)

        let replacementStartOffset = text.distance(from: text.startIndex, to: selection.lowerBound)
        let cursorOffset: Int = if selectedText.isEmpty {
            replacementStartOffset + 1
        } else {
            replacementStartOffset + 1 + selectedText.count + 2 + "https://".count
        }
        let cursor = result.index(result.startIndex, offsetBy: cursorOffset)

        return MarkdownFormattingResult(text: result, selection: cursor..<cursor)
    }

    /// Inserts the app's starter table at the cursor and keeps the cursor after the table.
    static func applyTableResult(to text: String, selection: Range<String.Index>) -> MarkdownFormattingResult {
        let insertionPoint = selection.lowerBound
        let suffix = text[insertionPoint...]
        let leadingBreak = needsLeadingLineBreak(in: text, at: insertionPoint) ? "\n" : ""
        let trailingBreak = suffix.isEmpty || suffix.hasPrefix("\n") ? "" : "\n"
        let replacement = "\(leadingBreak)\(tableMarkdown)\(trailingBreak)"
        var result = text

        result.replaceSubrange(insertionPoint..<insertionPoint, with: replacement)

        let insertionOffset = text.distance(from: text.startIndex, to: insertionPoint)
        let cursorOffset = insertionOffset + leadingBreak.count + tableMarkdown.count
        let cursor = result.index(result.startIndex, offsetBy: cursorOffset)

        return MarkdownFormattingResult(text: result, selection: cursor..<cursor)
    }

    /// Inserts an image link as a block when needed, preserving selected alt text.
    static func applyImageResult(
        to text: String,
        selection: Range<String.Index>,
        source: String
    ) -> MarkdownFormattingResult {
        let selectedText = String(text[selection])
        let insertionPoint = selection.lowerBound
        let suffix = text[selection.upperBound...]
        let leadingBreak = needsLeadingLineBreak(in: text, at: insertionPoint) ? "\n" : ""
        let trailingBreak = suffix.isEmpty || suffix.hasPrefix("\n") ? "" : "\n"
        let imageMarkdown = "![\(selectedText)](\(source))"
        let replacement = "\(leadingBreak)\(imageMarkdown)\(trailingBreak)"
        var result = text

        result.replaceSubrange(selection, with: replacement)

        let insertionOffset = text.distance(from: text.startIndex, to: insertionPoint)
        let cursorOffset = insertionOffset + leadingBreak.count + imageMarkdown.count
        let cursor = result.index(result.startIndex, offsetBy: cursorOffset)

        return MarkdownFormattingResult(text: result, selection: cursor..<cursor)
    }

    /// Inserts a local attachment link as a block while retaining its display label.
    static func applyAttachmentLinkResult(
        to text: String,
        selection: Range<String.Index>,
        label: String,
        source: String
    ) -> MarkdownFormattingResult {
        let insertionPoint = selection.lowerBound
        let suffix = text[selection.upperBound...]
        let leadingBreak = needsLeadingLineBreak(in: text, at: insertionPoint) ? "\n" : ""
        let trailingBreak = suffix.isEmpty || suffix.hasPrefix("\n") ? "" : "\n"
        let attachmentMarkdown = "[\(label)](\(source))"
        let replacement = "\(leadingBreak)\(attachmentMarkdown)\(trailingBreak)"
        var result = text

        result.replaceSubrange(selection, with: replacement)

        let insertionOffset = text.distance(from: text.startIndex, to: insertionPoint)
        let cursorOffset = insertionOffset + leadingBreak.count + attachmentMarkdown.count
        let cursor = result.index(result.startIndex, offsetBy: cursorOffset)

        return MarkdownFormattingResult(text: result, selection: cursor..<cursor)
    }

    /// Prefixes every selected line with an unordered-list marker.
    static func applyUnorderedListResult(to text: String, selection: Range<String.Index>) -> MarkdownFormattingResult {
        applyLinePrefixResult(to: text, selection: selection, prefix: "- ")
    }

    /// Prefixes selected lines with sequential ordered-list markers.
    static func applyOrderedListResult(to text: String, selection: Range<String.Index>) -> MarkdownFormattingResult {
        applyOrderedLinePrefixResult(to: text, selection: selection)
    }

    /// Prefixes selected lines with blockquote markers.
    static func applyQuoteResult(to text: String, selection: Range<String.Index>) -> MarkdownFormattingResult {
        applyLinePrefixResult(to: text, selection: selection, prefix: "> ")
    }

    /// Prefixes selected lines with unchecked task-list markers.
    static func applyTodoResult(to text: String, selection: Range<String.Index>) -> MarkdownFormattingResult {
        if selection.isEmpty {
            return resultPrefixingTodoContainingLine(
                in: text,
                cursor: selection.lowerBound
            )
        }

        let lineRange = expandedSelectedLineRange(in: text, for: selection)
        let lines = String(text[lineRange]).split(separator: "\n", omittingEmptySubsequences: false)
        let replacement = lines
            .map { todoLineTransformation(for: $0).text }
            .joined(separator: "\n")

        return resultReplacingLineRange(lineRange, in: text, with: replacement)
    }

    /// Toggles one rendered task marker while preserving every other source byte in the note.
    static func togglingTask(
        in text: String,
        marker: MarkdownTaskMarker,
        to state: MarkdownTaskState
    ) -> String? {
        guard marker.state != state else {
            return nil
        }

        var bytes = Array(text.utf8)
        guard let offset = taskMarkerOffset(in: bytes, marker: marker),
              bytes[offset] == 91,
              bytes[offset + 2] == 93,
              taskState(for: bytes[offset + 1]) == marker.state
        else {
            return nil
        }

        bytes[offset + 1] = switch state {
        case .checked:
            120
        case .unchecked:
            32
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    /// Replaces heading syntax on each selected line with the requested level.
    static func applyHeadingResult(
        level: MarkdownHeadingLevel,
        to text: String,
        selection: Range<String.Index>
    ) -> MarkdownFormattingResult {
        let lineRange = lineRange(in: text, containing: selection.lowerBound)
        let selectedText = String(text[lineRange])
        let strippedText = selectedText.removingMarkdownHeadingPrefix()
        let replacement = "\(level.markdownPrefix)\(strippedText)"
        var result = text

        result.replaceSubrange(lineRange, with: replacement)

        let lineStartOffset = text.distance(from: text.startIndex, to: lineRange.lowerBound)
        let cursorOffset = selection.isEmpty
            ? lineStartOffset + level.markdownPrefix.count
            : lineStartOffset + replacement.count
        let cursor = result.index(result.startIndex, offsetBy: cursorOffset)

        return MarkdownFormattingResult(text: result, selection: cursor..<cursor)
    }

    /// Applies a symmetric wrapper and selects the inserted content rather than the markers.
    private static func applyWrappedResult(
        to text: String,
        selection: Range<String.Index>,
        prefix: String,
        suffix: String
    ) -> MarkdownFormattingResult {
        let selectedText = String(text[selection])
        let replacement = "\(prefix)\(selectedText)\(suffix)"
        var result = text

        result.replaceSubrange(selection, with: replacement)

        let replacementOffset = selectedText.isEmpty ? prefix.count : replacement.count
        let cursorOffset = text.distance(from: text.startIndex, to: selection.lowerBound) + replacementOffset
        let cursor = result.index(result.startIndex, offsetBy: cursorOffset)

        return MarkdownFormattingResult(text: result, selection: cursor..<cursor)
    }

    /// Convenience heading API used when only the transformed text is needed.
    static func applyHeading(level: MarkdownHeadingLevel, to text: String, selection: Range<String.Index>?) -> String {
        let selectedRange = selection ?? text.endIndex..<text.endIndex
        return applyHeadingResult(level: level, to: text, selection: selectedRange).text
    }

    private static let tableMarkdown = """
    | Header 1 | Header 2 |
    | --- | --- |
    |  |  |
    |  |  |
    """

    /// Adds a prefix to a line range while returning offsets in the new string.
    private static func prefixLines(_ text: String, range: Range<String.Index>, prefix: String) -> String {
        applyLinePrefixResult(to: text, selection: range, prefix: prefix).text
    }

    /// Adds numbered prefixes, restarting numbering at one for the selected range.
    private static func prefixOrderedLines(_ text: String, range: Range<String.Index>) -> String {
        applyOrderedLinePrefixResult(to: text, selection: range).text
    }

    /// Builds a selection result for line-based replacements and accounts for inserted newlines.
    private static func applyLinePrefixResult(
        to text: String,
        selection: Range<String.Index>,
        prefix: String
    ) -> MarkdownFormattingResult {
        if selection.isEmpty {
            return resultPrefixingContainingLine(
                in: text,
                cursor: selection.lowerBound,
                prefix: prefix
            ) { !$0.hasPrefix(prefix) }
        }

        let lineRange = expandedSelectedLineRange(in: text, for: selection)
        let lines = String(text[lineRange]).split(separator: "\n", omittingEmptySubsequences: false)
        let replacement = lines.map { line in
            line.hasPrefix(prefix) ? String(line) : "\(prefix)\(line)"
        }.joined(separator: "\n")

        return resultReplacingLineRange(lineRange, in: text, with: replacement)
    }

    /// Builds the ordered-list variant of the line-prefix result.
    private static func applyOrderedLinePrefixResult(
        to text: String,
        selection: Range<String.Index>
    ) -> MarkdownFormattingResult {
        if selection.isEmpty {
            return resultPrefixingContainingLine(
                in: text,
                cursor: selection.lowerBound,
                prefix: "1. "
            ) { _ in true }
        }

        let lineRange = expandedSelectedLineRange(in: text, for: selection)
        let lines = String(text[lineRange]).split(separator: "\n", omittingEmptySubsequences: false)
        let replacement = lines.enumerated().map { index, line in
            "\(index + 1). \(line)"
        }.joined(separator: "\n")

        return resultReplacingLineRange(lineRange, in: text, with: replacement)
    }

    /// Replaces a source line range and maps the cursor to the end of the replacement.
    private static func resultReplacingLineRange(
        _ lineRange: Range<String.Index>,
        in text: String,
        with replacement: String
    ) -> MarkdownFormattingResult {
        var result = text
        result.replaceSubrange(lineRange, with: replacement)
        let cursorOffset = text.distance(from: text.startIndex, to: lineRange.lowerBound) + replacement.count
        let cursor = result.index(result.startIndex, offsetBy: cursorOffset)

        return MarkdownFormattingResult(text: result, selection: cursor..<cursor)
    }

    /// Prefixes the containing line when the cursor selection is empty.
    private static func resultPrefixingContainingLine(
        in text: String,
        cursor: String.Index,
        prefix: String,
        shouldPrefixLine: (Substring) -> Bool
    ) -> MarkdownFormattingResult {
        let lineRange = lineRange(in: text, containing: cursor)
        let line = text[lineRange]

        guard shouldPrefixLine(line) else {
            return MarkdownFormattingResult(text: text, selection: cursor..<cursor)
        }

        var result = text
        result.replaceSubrange(lineRange.lowerBound..<lineRange.lowerBound, with: prefix)

        let cursorOffset = text.distance(from: text.startIndex, to: cursor) + prefix.count
        let adjustedCursor = result.index(result.startIndex, offsetBy: cursorOffset)

        return MarkdownFormattingResult(text: result, selection: adjustedCursor..<adjustedCursor)
    }

    /// Expands a character selection to whole lines while avoiding an accidental extra blank line.
    private static func expandedSelectedLineRange(
        in text: String,
        for range: Range<String.Index>
    ) -> Range<String.Index> {
        let lower = text[..<range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let upperBound = trimmedTrailingLineBreakUpperBound(for: range, in: text)
        let upper = text[upperBound...].firstIndex(of: "\n") ?? text.endIndex

        return lower..<upper
    }

    /// Keeps a trailing newline outside the editable line range when it is only a boundary.
    private static func trimmedTrailingLineBreakUpperBound(
        for range: Range<String.Index>,
        in text: String
    ) -> String.Index {
        guard !range.isEmpty,
              range.upperBound > text.startIndex
        else {
            return range.upperBound
        }

        let previousIndex = text.index(before: range.upperBound)
        guard text[previousIndex] == "\n" else {
            return range.upperBound
        }

        return previousIndex
    }

    /// Returns the full logical line containing a source index.
    private static func lineRange(in text: String, containing index: String.Index) -> Range<String.Index> {
        let lower = text[..<index].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let upper = text[index...].firstIndex(of: "\n") ?? text.endIndex
        return lower..<upper
    }

    /// Determines whether a block insertion needs a separator before the current cursor.
    private static func needsLeadingLineBreak(in text: String, at index: String.Index) -> Bool {
        guard index > text.startIndex else {
            return false
        }

        return text[text.index(before: index)] != "\n"
    }
}

private extension MarkdownFormatting {
    /// Resolves a one-based UTF-8 task location without converting Unicode source to character offsets.
    static func taskMarkerOffset(in bytes: [UInt8], marker: MarkdownTaskMarker) -> Int? {
        guard marker.line > 0, marker.column > 0 else {
            return nil
        }

        var line = 1
        var lineStart = 0
        while line < marker.line {
            guard let newlineOffset = bytes[lineStart...].firstIndex(of: 10) else {
                return nil
            }
            lineStart = newlineOffset + 1
            line += 1
        }

        let offset = lineStart + marker.column - 1
        guard offset + 2 < bytes.count else {
            return nil
        }
        return offset
    }

    /// Converts the ASCII task-marker byte into the corresponding Markdown task state.
    static func taskState(for byte: UInt8) -> MarkdownTaskState? {
        switch byte {
        case 32:
            .unchecked
        case 88, 120:
            .checked
        default:
            nil
        }
    }

    /// Applies task syntax to one line while preserving existing task markers and bare list markers.
    static func resultPrefixingTodoContainingLine(
        in text: String,
        cursor: String.Index
    ) -> MarkdownFormattingResult {
        let lineRange = lineRange(in: text, containing: cursor)
        let line = text[lineRange]

        guard !hasTaskMarker(line) else {
            return MarkdownFormattingResult(text: text, selection: cursor..<cursor)
        }

        let transformation = todoLineTransformation(for: line)
        var result = text
        result.replaceSubrange(lineRange, with: transformation.text)

        let lineStartOffset = text.distance(from: text.startIndex, to: lineRange.lowerBound)
        let cursorOffsetInLine = text.distance(from: lineRange.lowerBound, to: cursor)
        let replacementCursorOffsetInLine = cursorOffsetInLine <= transformation.consumedPrefixLength
            ? todoPrefix.count
            : todoPrefix.count + cursorOffsetInLine - transformation.consumedPrefixLength
        let cursorOffset = lineStartOffset + replacementCursorOffsetInLine
        let adjustedCursor = result.index(result.startIndex, offsetBy: cursorOffset)

        return MarkdownFormattingResult(text: result, selection: adjustedCursor..<adjustedCursor)
    }

    /// Replaces a bare unindented list marker without treating it as task content.
    static func todoLineTransformation(for line: Substring) -> TodoLineTransformation {
        guard !hasTaskMarker(line) else {
            return TodoLineTransformation(text: String(line), consumedPrefixLength: 0)
        }

        guard let markerEnd = bareListMarkerEnd(in: line) else {
            return TodoLineTransformation(text: "\(todoPrefix)\(line)", consumedPrefixLength: 0)
        }

        return TodoLineTransformation(
            text: "\(todoPrefix)\(line[markerEnd...])",
            consumedPrefixLength: line.distance(from: line.startIndex, to: markerEnd)
        )
    }

    /// Finds a bare list marker at column zero, excluding thematic breaks.
    static func bareListMarkerEnd(in line: Substring) -> Substring.Index? {
        guard line.first == "-" else {
            return nil
        }

        let markerEnd = line.index(after: line.startIndex)
        guard markerEnd == line.endIndex || isHorizontalWhitespace(line[markerEnd]) else {
            return nil
        }

        guard !isThematicBreak(line) else {
            return nil
        }

        var contentStart = markerEnd
        while contentStart < line.endIndex, isHorizontalWhitespace(line[contentStart]) {
            contentStart = line.index(after: contentStart)
        }

        return contentStart
    }

    /// Keeps checkbox markers unchanged, including Markdown's optional three-space indentation.
    static func hasTaskMarker(_ line: Substring) -> Bool {
        var markerStart = line.startIndex
        var leadingSpaceCount = 0
        while leadingSpaceCount < 3 && markerStart < line.endIndex && line[markerStart] == " " {
            leadingSpaceCount += 1
            markerStart = line.index(after: markerStart)
        }

        let content = line[markerStart...]
        for marker in ["- [ ]", "- [x]", "- [X]"] {
            guard content.hasPrefix(marker) else {
                continue
            }

            let suffixStart = content.index(content.startIndex, offsetBy: marker.count)
            return suffixStart == content.endIndex || isHorizontalWhitespace(content[suffixStart])
        }

        return false
    }

    /// Distinguishes hyphen-only thematic breaks from a bare list marker.
    static func isThematicBreak(_ line: Substring) -> Bool {
        var hyphenCount = 0

        for character in line {
            if character == "-" {
                hyphenCount += 1
            } else if !isHorizontalWhitespace(character) {
                return false
            }
        }

        return hyphenCount >= 3
    }

    static func isHorizontalWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }

    static let todoPrefix = "- [ ] "

    struct TodoLineTransformation {
        let text: String
        let consumedPrefixLength: Int
    }
}

private extension Substring {
    func removingMarkdownHeadingPrefix() -> Substring {
        var currentIndex = startIndex
        var markerCount = 0

        while currentIndex < endIndex, self[currentIndex] == "#", markerCount < 6 {
            markerCount += 1
            currentIndex = index(after: currentIndex)
        }

        guard markerCount > 0, currentIndex < endIndex, self[currentIndex] == " " else {
            return self
        }

        return self[index(after: currentIndex)...]
    }
}

private extension String {
    func removingMarkdownHeadingPrefix() -> Substring {
        self[...].removingMarkdownHeadingPrefix()
    }
}
