import Foundation

struct MarkdownFormattingResult: Equatable {
    let text: String
    let selection: Range<String.Index>
}

enum MarkdownFormatting {
    static func apply(_ command: NoteFormattingCommand, to text: String, selection: Range<String.Index>?) -> String {
        let selectedRange = selection ?? text.endIndex..<text.endIndex

        switch command {
        case .bold:
            return applyBoldResult(to: text, selection: selectedRange).text
        case .italic:
            return applyItalicResult(to: text, selection: selectedRange).text
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

    static func applyBoldResult(to text: String, selection: Range<String.Index>) -> MarkdownFormattingResult {
        applyWrappedResult(to: text, selection: selection, prefix: "**", suffix: "**")
    }

    static func applyItalicResult(to text: String, selection: Range<String.Index>) -> MarkdownFormattingResult {
        applyWrappedResult(to: text, selection: selection, prefix: "_", suffix: "_")
    }

    static func applyCodeResult(to text: String, selection: Range<String.Index>) -> MarkdownFormattingResult {
        applyWrappedResult(to: text, selection: selection, prefix: "`", suffix: "`")
    }

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

    static func applyUnorderedListResult(to text: String, selection: Range<String.Index>) -> MarkdownFormattingResult {
        applyLinePrefixResult(to: text, selection: selection, prefix: "- ")
    }

    static func applyOrderedListResult(to text: String, selection: Range<String.Index>) -> MarkdownFormattingResult {
        applyOrderedLinePrefixResult(to: text, selection: selection)
    }

    static func applyQuoteResult(to text: String, selection: Range<String.Index>) -> MarkdownFormattingResult {
        applyLinePrefixResult(to: text, selection: selection, prefix: "> ")
    }

    static func applyTodoResult(to text: String, selection: Range<String.Index>) -> MarkdownFormattingResult {
        applyLinePrefixResult(to: text, selection: selection, prefix: "- [ ] ")
    }

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

    private static func prefixLines(_ text: String, range: Range<String.Index>, prefix: String) -> String {
        applyLinePrefixResult(to: text, selection: range, prefix: prefix).text
    }

    private static func prefixOrderedLines(_ text: String, range: Range<String.Index>) -> String {
        applyOrderedLinePrefixResult(to: text, selection: range).text
    }

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

    private static func expandedSelectedLineRange(
        in text: String,
        for range: Range<String.Index>
    ) -> Range<String.Index> {
        let lower = text[..<range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let upperBound = trimmedTrailingLineBreakUpperBound(for: range, in: text)
        let upper = text[upperBound...].firstIndex(of: "\n") ?? text.endIndex

        return lower..<upper
    }

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

    private static func lineRange(in text: String, containing index: String.Index) -> Range<String.Index> {
        let lower = text[..<index].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let upper = text[index...].firstIndex(of: "\n") ?? text.endIndex
        return lower..<upper
    }

    private static func needsLeadingLineBreak(in text: String, at index: String.Index) -> Bool {
        guard index > text.startIndex else {
            return false
        }

        return text[text.index(before: index)] != "\n"
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
