import Foundation

/// Describes a standalone hashtag line and the selection-preserving edit that removes it.
struct NoteTagEntry: Equatable {
    let tag: NoteTag
    let result: MarkdownFormattingResult
}

/// Recognizes tags only where they are standalone Markdown-like entries, not prose or code.
enum NoteTagEntryParser {
    static func entry(in text: String, selection: MarkdownEditorSelectionSnapshot) -> NoteTagEntry? {
        guard selection.isEmpty else {
            return nil
        }

        let cursor = stringIndex(atUTF16Offset: selection.lowerOffset, in: text)
        let lineRange = lineRange(containing: cursor, in: text)
        let line = String(text[lineRange])
        guard text[lineRange.lowerBound..<cursor].trimmingCharacters(in: .whitespaces).count
            == line.trimmingCharacters(in: .whitespaces).count
        else {
            return nil
        }
        guard text[cursor..<lineRange.upperBound].trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        guard !isInsideFencedCodeBlock(before: lineRange.lowerBound, in: text) else {
            return nil
        }

        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        let rawTag = trimmedLine.dropFirst()
        guard trimmedLine.hasPrefix("#"),
              let firstCharacter = rawTag.first,
              !firstCharacter.isWhitespace,
              let tag = NoteTag(String(rawTag))
        else {
            return nil
        }

        let removalRange = removalRange(for: lineRange, in: text)
        var updatedText = text
        updatedText.removeSubrange(removalRange)

        let cursorOffset = text.distance(from: text.startIndex, to: removalRange.lowerBound)
        let updatedCursor = updatedText.index(
            updatedText.startIndex,
            offsetBy: min(cursorOffset, updatedText.count)
        )
        return NoteTagEntry(
            tag: tag,
            result: MarkdownFormattingResult(
                text: updatedText,
                selection: updatedCursor..<updatedCursor
            )
        )
    }

    private static func lineRange(containing index: String.Index, in text: String) -> Range<String.Index> {
        let lowerBound = text[..<index].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let upperBound = text[index...].firstIndex(of: "\n") ?? text.endIndex
        return lowerBound..<upperBound
    }

    private static func removalRange(
        for lineRange: Range<String.Index>,
        in text: String
    ) -> Range<String.Index> {
        let hasTrailingNewline = lineRange.upperBound < text.endIndex
            && text[lineRange.upperBound] == "\n"
        if hasTrailingNewline {
            return lineRange.lowerBound..<text.index(after: lineRange.upperBound)
        }

        if lineRange.lowerBound > text.startIndex {
            return text.index(before: lineRange.lowerBound)..<lineRange.upperBound
        }

        return lineRange
    }

    private static func isInsideFencedCodeBlock(before lineStart: String.Index, in text: String) -> Bool {
        var current = text.startIndex
        var isInsideFence = false

        while current < lineStart {
            let lineEnd = text[current...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[current..<lineEnd]
            if isFenceLine(line) {
                isInsideFence.toggle()
            }
            current = lineEnd == text.endIndex ? text.endIndex : text.index(after: lineEnd)
        }

        return isInsideFence
    }

    private static func isFenceLine(_ line: Substring) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        return trimmedLine.hasPrefix("```") || trimmedLine.hasPrefix("~~~")
    }

    private static func stringIndex(atUTF16Offset offset: Int, in text: String) -> String.Index {
        let clampedOffset = min(max(offset, 0), text.utf16.count)
        let utf16Index = text.utf16.index(text.utf16.startIndex, offsetBy: clampedOffset)
        return String.Index(utf16Index, within: text) ?? text.endIndex
    }
}
