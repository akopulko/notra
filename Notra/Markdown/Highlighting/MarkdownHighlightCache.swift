import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

#if os(macOS)
extension MarkdownHighlightCache {
    /// Draws syntax colours without mutating the text storage that owns AppKit's insertion point.
    func applyTemporaryColors(
        theme: MarkdownTheme,
        font: MarkdownPlatformFont,
        baseColor: MarkdownPlatformColor,
        to layoutManager: NSLayoutManager,
        lines: Range<Int>
    ) {
        let clampedRange = lines.clamped(to: 0..<self.lines.count)
        guard !clampedRange.isEmpty else {
            return
        }

        for lineIndex in clampedRange {
            let line = self.lines[lineIndex]
            let characterRange = NSRange(
                location: line.range.lowerBound,
                length: line.range.upperBound - line.range.lowerBound
            )
            guard characterRange.length > 0 else {
                continue
            }

            layoutManager.setTemporaryAttributes(
                [.font: font, .foregroundColor: baseColor],
                forCharacterRange: characterRange
            )

            for span in line.spans {
                let spanRange = NSRange(location: span.lower, length: span.upper - span.lower)
                guard spanRange.length > 0 else {
                    continue
                }

                layoutManager.addTemporaryAttribute(
                    .foregroundColor,
                    value: theme.color(for: span.role).platformColor,
                    forCharacterRange: spanRange
                )
            }
        }
    }
}
#endif

/// Stores a syntax span using the offset unit expected by UITextView and NSTextView.
struct MarkdownUTF16Span: Equatable {
    let role: MarkdownHighlightRole
    let lower: Int
    let upper: Int
}

/// Caches the parsed result for one line so edits can reparse only affected regions.
struct MarkdownLineHighlight {
    let range: Range<Int>
    let spans: [MarkdownUTF16Span]
    let fenceStateBefore: MarkdownCodeFenceState
    let fenceStateAfter: MarkdownCodeFenceState

    var opensFence: Bool {
        fenceStateBefore.isInFence != fenceStateAfter.isInFence
    }

    var isInFence: Bool {
        fenceStateBefore.isInFence
    }
}

/// Maintains incremental syntax-highlight state as the editor text changes.
struct MarkdownHighlightCache {
    private(set) var text = ""
    private(set) var lines: [MarkdownLineHighlight] = []

    var count: Int {
        lines.count
    }

    var isEmpty: Bool {
        lines.isEmpty
    }

    /// Rebuilds every cached line; used for initial load and full-refresh fallback paths.
    mutating func setText(_ newText: String) {
        text = newText
        lines = Self.buildLines(for: newText)
    }

    /// Reparses the smallest affected line region while carrying fence state from its prefix.
    @discardableResult
    mutating func updateText(_ newText: String, edit: MarkdownTextEdit? = nil) -> Range<Int>? {
        guard newText != text else {
            return nil
        }

        if let edit, let changedRange = updateText(newText, using: edit) {
            return changedRange
        }

        let oldText = text
        text = newText

        let oldEntries = Self.lineEntries(for: oldText)
        let newEntries = Self.lineEntries(for: newText)

        var prefix = 0
        let minCount = Swift.min(oldEntries.count, newEntries.count)
        while prefix < minCount, oldEntries[prefix].content == newEntries[prefix].content {
            prefix += 1
        }

        var suffix = 0
        while suffix < minCount - prefix {
            let oldLine = oldEntries[oldEntries.count - 1 - suffix]
            let newLine = newEntries[newEntries.count - 1 - suffix]
            guard oldLine.content == newLine.content else {
                break
            }
            suffix += 1
        }

        var changedCount = newEntries.count - prefix - suffix
        let oldCache = lines

        let delimiterRowAbovePrefix = prefix > 0
            && (
                (prefix < oldEntries.count && MarkdownSyntaxHighlighter.isTableDelimiterRow(oldEntries[prefix].content))
                    || (prefix < newEntries.count && MarkdownSyntaxHighlighter.isTableDelimiterRow(newEntries[prefix].content))
            )

        if delimiterRowAbovePrefix {
            prefix -= 1
            changedCount += 1
        }

        let initialFenceState = prefix > 0
            ? oldCache[prefix - 1].fenceStateAfter
            : MarkdownCodeFenceState.closed
        var fenceState = initialFenceState

        var updatedLines = Array(oldCache.prefix(prefix))
        var changedRange = prefix..<prefix + changedCount
        let highlighter = MarkdownSyntaxHighlighter()

        for index in 0..<changedCount {
            let entryIndex = prefix + index
            Self.appendParsedLine(
                entry: newEntries[entryIndex],
                highlighter: highlighter,
                fenceState: &fenceState,
                nextLine: newEntries.count > entryIndex + 1 ? newEntries[entryIndex + 1].content : nil,
                into: &updatedLines
            )
        }

        for index in 0..<suffix {
            let newLineIndex = newEntries.count - suffix + index
            let oldLineIndex = oldCache.count - suffix + index
            guard fenceState != oldCache[oldLineIndex].fenceStateBefore else {
                break
            }
            Self.appendParsedLine(
                entry: newEntries[newLineIndex],
                highlighter: highlighter,
                fenceState: &fenceState,
                nextLine: newEntries.count > newLineIndex + 1 ? newEntries[newLineIndex + 1].content : nil,
                into: &updatedLines
            )
            changedRange = changedRange.lowerBound..<newLineIndex + 1
        }

        for newLineIndex in changedRange.upperBound..<newEntries.count {
            let oldLineIndex = oldCache.count - (newEntries.count - newLineIndex)
            let oldLine = oldCache[oldLineIndex]
            let spanDelta = newEntries[newLineIndex].range.lowerBound - oldLine.range.lowerBound
            let spans = oldLine.spans.map { span in
                MarkdownUTF16Span(
                    role: span.role,
                    lower: span.lower + spanDelta,
                    upper: span.upper + spanDelta
                )
            }
            updatedLines.append(
                MarkdownLineHighlight(
                    range: newEntries[newLineIndex].range,
                    spans: spans,
                    fenceStateBefore: oldLine.fenceStateBefore,
                    fenceStateAfter: oldLine.fenceStateAfter
                )
            )
        }

        lines = updatedLines
        return changedRange
    }

    func line(at index: Int) -> MarkdownLineHighlight {
        lines[index]
    }

    func applyColors(
        theme: MarkdownTheme,
        font: MarkdownPlatformFont,
        baseColor: MarkdownPlatformColor,
        to storage: NSMutableAttributedString,
        lines: Range<Int>
    ) {
        let clampedRange = lines.clamped(to: 0..<self.lines.count)
        guard !clampedRange.isEmpty else {
            return
        }

        storage.beginEditing()
        defer { storage.endEditing() }

        for lineIndex in clampedRange {
            let line = self.lines[lineIndex]
            let lineStart = min(line.range.lowerBound, storage.length)
            let lineEnd = min(line.range.upperBound, storage.length)
            guard lineEnd > lineStart else {
                continue
            }

            storage.setAttributes(
                [.font: font, .foregroundColor: baseColor],
                range: NSRange(location: lineStart, length: lineEnd - lineStart)
            )

            for span in line.spans {
                let spanStart = min(max(span.lower, lineStart), lineEnd)
                let spanEnd = min(max(span.upper, spanStart), lineEnd)
                guard spanEnd > spanStart else {
                    continue
                }

                storage.addAttribute(
                    .foregroundColor,
                    value: theme.color(for: span.role).platformColor,
                    range: NSRange(location: spanStart, length: spanEnd - spanStart)
                )
            }
        }
    }

    private static func appendParsedLine(
        entry: (range: Range<Int>, content: String),
        highlighter: MarkdownSyntaxHighlighter,
        fenceState: inout MarkdownCodeFenceState,
        nextLine: String?,
        into lines: inout [MarkdownLineHighlight]
    ) {
        let parsed = highlighter.parseLine(entry.content, fenceState: fenceState, nextLine: nextLine)
        let spans = parsed.spans.map { span in
            MarkdownUTF16Span(
                role: span.role,
                lower: entry.range.lowerBound + span.range.lowerBound.utf16Offset(in: entry.content),
                upper: entry.range.lowerBound + span.range.upperBound.utf16Offset(in: entry.content)
            )
        }
        lines.append(
            MarkdownLineHighlight(
                range: entry.range,
                spans: spans,
                fenceStateBefore: fenceState,
                fenceStateAfter: parsed.fenceStateAfter
            )
        )
        fenceState = parsed.fenceStateAfter
    }

    /// Uses native edit metadata to avoid scanning matching prefixes and suffixes in large notes.
    private mutating func updateText(_ newText: String, using edit: MarkdownTextEdit) -> Range<Int>? {
        guard edit.range.location != NSNotFound,
              edit.range.location >= 0,
              edit.range.length >= 0,
              edit.range.location + edit.range.length <= text.utf16.count,
              edit.replacementUTF16Length >= 0,
              newText.utf16.count == text.utf16.count - edit.range.length + edit.replacementUTF16Length
        else {
            return nil
        }

        let oldText = text
        let oldCache = lines
        let newEntries = Self.lineEntries(for: newText)
        let editedOldUpper = edit.range.location + edit.range.length
        let editedNewUpper = edit.range.location + edit.replacementUTF16Length

        guard let oldEndLine = Self.lineIndex(in: oldCache, containingOrPreceding: max(edit.range.location, editedOldUpper)),
              let newStartLine = Self.lineIndex(in: newEntries, containingOrPreceding: edit.range.location),
              let newEndLine = Self.lineIndex(in: newEntries, containingOrPreceding: max(edit.range.location, editedNewUpper))
        else {
            return nil
        }

        let parseStart = shouldReparsePreviousLine(
            oldText: oldText,
            oldEntries: oldCache,
            newEntries: newEntries,
            at: newStartLine
        ) ? max(newStartLine - 1, 0) : newStartLine
        text = newText
        let oldSuffixStart = min(oldEndLine + 1, oldCache.count)
        let newChangedEnd = min(newEndLine + 1, newEntries.count)

        let initialFenceState = parseStart > 0
            ? oldCache[parseStart - 1].fenceStateAfter
            : MarkdownCodeFenceState.closed
        var fenceState = initialFenceState

        var updatedLines = Array(oldCache.prefix(parseStart))
        var changedRange = parseStart..<newChangedEnd
        let highlighter = MarkdownSyntaxHighlighter()

        for entryIndex in parseStart..<newChangedEnd {
            Self.appendParsedLine(
                entry: newEntries[entryIndex],
                highlighter: highlighter,
                fenceState: &fenceState,
                nextLine: newEntries.count > entryIndex + 1 ? newEntries[entryIndex + 1].content : nil,
                into: &updatedLines
            )
        }

        var oldSuffixIndex = oldSuffixStart
        var newSuffixIndex = newChangedEnd
        while shouldRehighlightSuffixLine(
            oldCache: oldCache,
            oldIndex: oldSuffixIndex,
            newEntries: newEntries,
            newIndex: newSuffixIndex,
            fenceState: fenceState
        ) {
            Self.appendParsedLine(
                entry: newEntries[newSuffixIndex],
                highlighter: highlighter,
                fenceState: &fenceState,
                nextLine: newEntries.count > newSuffixIndex + 1 ? newEntries[newSuffixIndex + 1].content : nil,
                into: &updatedLines
            )
            oldSuffixIndex += 1
            newSuffixIndex += 1
            changedRange = changedRange.lowerBound..<newSuffixIndex
        }

        for newLineIndex in newSuffixIndex..<newEntries.count {
            guard oldSuffixIndex < oldCache.count else {
                return nil
            }

            let oldLine = oldCache[oldSuffixIndex]
            let offsetDelta = newEntries[newLineIndex].range.lowerBound - oldLine.range.lowerBound
            updatedLines.append(
                MarkdownLineHighlight(
                    range: newEntries[newLineIndex].range,
                    spans: oldLine.spans.map { span in
                        MarkdownUTF16Span(
                            role: span.role,
                            lower: span.lower + offsetDelta,
                            upper: span.upper + offsetDelta
                        )
                    },
                    fenceStateBefore: oldLine.fenceStateBefore,
                    fenceStateAfter: oldLine.fenceStateAfter
                )
            )
            oldSuffixIndex += 1
        }

        guard updatedLines.count == newEntries.count else {
            return nil
        }

        lines = updatedLines
        return changedRange
    }

    private func shouldReparsePreviousLine(
        oldText: String,
        oldEntries: [MarkdownLineHighlight],
        newEntries: [(range: Range<Int>, content: String)],
        at index: Int
    ) -> Bool {
        guard index > 0 else {
            return false
        }

        let oldCurrentIsDelimiter = index < oldEntries.count
            && MarkdownSyntaxHighlighter.isTableDelimiterRow(
                Self.lineContent(for: oldEntries[index], in: oldText)
            )
        let newCurrentIsDelimiter = index < newEntries.count
            && MarkdownSyntaxHighlighter.isTableDelimiterRow(newEntries[index].content)
        return oldCurrentIsDelimiter || newCurrentIsDelimiter
    }

    private func shouldRehighlightSuffixLine(
        oldCache: [MarkdownLineHighlight],
        oldIndex: Int,
        newEntries: [(range: Range<Int>, content: String)],
        newIndex: Int,
        fenceState: MarkdownCodeFenceState
    ) -> Bool {
        oldIndex < oldCache.count
            && newIndex < newEntries.count
            && fenceState != oldCache[oldIndex].fenceStateBefore
    }

    private static func lineEntries(for text: String) -> [(range: Range<Int>, content: String)] {
        var entries: [(range: Range<Int>, content: String)] = []
        var lineStart = text.startIndex

        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let content = String(text[lineStart..<lineEnd])
            let range = lineStart.utf16Offset(in: text)..<lineEnd.utf16Offset(in: text)
            entries.append((range, content))

            if lineEnd == text.endIndex {
                break
            }

            lineStart = text.index(after: lineEnd)
        }

        return entries
    }

    private static func buildLines(for text: String) -> [MarkdownLineHighlight] {
        var lines: [MarkdownLineHighlight] = []
        var fenceState = MarkdownCodeFenceState.closed
        let highlighter = MarkdownSyntaxHighlighter()
        let entries = lineEntries(for: text)

        for (index, entry) in entries.enumerated() {
            let nextLine = entries.count > index + 1 ? entries[index + 1].content : nil
            let parsed = highlighter.parseLine(entry.content, fenceState: fenceState, nextLine: nextLine)
            let spans = parsed.spans.map { span in
                MarkdownUTF16Span(
                    role: span.role,
                    lower: entry.range.lowerBound + span.range.lowerBound.utf16Offset(in: entry.content),
                    upper: entry.range.lowerBound + span.range.upperBound.utf16Offset(in: entry.content)
                )
            }
            lines.append(
                MarkdownLineHighlight(
                    range: entry.range,
                    spans: spans,
                    fenceStateBefore: fenceState,
                    fenceStateAfter: parsed.fenceStateAfter
                )
            )
            fenceState = parsed.fenceStateAfter
        }

        return lines
    }
}

private extension MarkdownHighlightCache {
    static func lineIndex(
        in entries: [MarkdownLineHighlight],
        containingOrPreceding offset: Int
    ) -> Int? {
        lineIndex(count: entries.count, rangeAt: { entries[$0].range }, containingOrPreceding: offset)
    }

    static func lineIndex(
        in entries: [(range: Range<Int>, content: String)],
        containingOrPreceding offset: Int
    ) -> Int? {
        lineIndex(count: entries.count, rangeAt: { entries[$0].range }, containingOrPreceding: offset)
    }

    static func lineIndex(
        count: Int,
        rangeAt: (Int) -> Range<Int>,
        containingOrPreceding offset: Int
    ) -> Int? {
        guard count > 0 else {
            return nil
        }

        var lowerBound = 0
        var upperBound = count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if rangeAt(middle).lowerBound <= offset {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        return max(lowerBound - 1, 0)
    }

    static func lineContent(for line: MarkdownLineHighlight, in text: String) -> String {
        (text as NSString).substring(
            with: NSRange(location: line.range.lowerBound, length: line.range.count)
        )
    }
}
