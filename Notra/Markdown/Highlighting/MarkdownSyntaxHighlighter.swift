import Foundation
import SwiftUI

/// Associates a syntax role with a UTF-16 range in the Markdown source.
struct MarkdownHighlightSpan: Equatable {
    let role: MarkdownHighlightRole
    let range: Range<String.Index>
}

/// Parses Markdown line-by-line into stable spans suitable for native text views.
struct MarkdownSyntaxHighlighter {
    /// Converts syntax spans into an attributed string for SwiftUI preview or native text views.
    func highlight(_ markdown: String, theme: MarkdownTheme) -> AttributedString {
        var attributed = AttributedString(markdown)

        for span in spans(in: markdown) {
            guard let lower = AttributedString.Index(span.range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(span.range.upperBound, within: attributed)
            else {
                continue
            }

            attributed[lower..<upper].foregroundColor = theme.color(for: span.role).color
        }

        return attributed
    }

    /// Parses the full document while carrying fence state from line to line.
    func spans(in markdown: String) -> [MarkdownHighlightSpan] {
        var spans: [MarkdownHighlightSpan] = []
        var lineStart = markdown.startIndex
        var fenceState = MarkdownCodeFenceState.closed

        while lineStart < markdown.endIndex {
            let lineEnd = markdown[lineStart...].firstIndex(of: "\n") ?? markdown.endIndex
            let nextLineStart = lineEnd == markdown.endIndex ? markdown.endIndex : markdown.index(after: lineEnd)
            let lineRange = lineStart..<lineEnd
            let nextLineEnd = nextLineStart == markdown.endIndex
                ? markdown.endIndex
                : markdown[nextLineStart...].firstIndex(of: "\n") ?? markdown.endIndex
            let nextLine = nextLineStart == markdown.endIndex ? nil : String(markdown[nextLineStart..<nextLineEnd])

            parseLine(
                markdown,
                range: lineRange,
                fenceState: &fenceState,
                nextLine: nextLine,
                spans: &spans
            )

            lineStart = nextLineStart
        }

        return spans
    }

    /// Test-friendly line parser that accepts the fence state as a simple Boolean.
    func parseLine(_ line: String, isInFence: Bool, nextLine: String? = nil) -> MarkdownLineParseResult {
        parseLine(
            line,
            fenceState: MarkdownCodeFenceState(isInFence: isInFence),
            nextLine: nextLine
        )
    }

    /// Parses one line and returns both spans and the state needed by the following line.
    func parseLine(
        _ line: String,
        fenceState initialFenceState: MarkdownCodeFenceState,
        nextLine: String? = nil
    ) -> MarkdownLineParseResult {
        var spans: [MarkdownHighlightSpan] = []
        var fenceState = initialFenceState
        parseLine(
            line,
            range: line.startIndex..<line.endIndex,
            fenceState: &fenceState,
            nextLine: nextLine,
            spans: &spans
        )
        return MarkdownLineParseResult(spans: spans, fenceStateAfter: fenceState)
    }

    private func parseLine(
        _ markdown: String,
        range: Range<String.Index>,
        fenceState: inout MarkdownCodeFenceState,
        nextLine: String?,
        spans: inout [MarkdownHighlightSpan]
    ) {
        let contentStart = firstNonSpace(in: markdown, range: range)

        if let markerEnd = codeFenceMarkerEnd(in: markdown, startingAt: contentStart, lineEnd: range.upperBound) {
            spans.append(MarkdownHighlightSpan(role: .codeFence, range: contentStart..<markerEnd))
            let languageRange = fenceLanguageIdentifierRange(
                in: markdown,
                after: markerEnd,
                lineEnd: range.upperBound
            )
            if !fenceState.isInFence, let languageRange {
                spans.append(MarkdownHighlightSpan(role: .codeLanguageIdentifier, range: languageRange))
            }
            fenceState = fenceState.isInFence
                ? .closed
                : MarkdownCodeFenceState(
                    isInFence: true,
                    language: fenceLanguage(in: markdown, after: markerEnd, lineEnd: range.upperBound)
                )
            return
        }

        guard !fenceState.isInFence else {
            appendCodeSpans(
                in: markdown,
                range: range,
                language: fenceState.language,
                spans: &spans
            )
            return
        }

        if parseThematicBreak(in: markdown, range: contentStart..<range.upperBound, spans: &spans) {
            return
        }

        if let inlineStart = parseHeading(in: markdown, range: contentStart..<range.upperBound, spans: &spans) {
            parseInlineMarkdown(in: markdown, range: inlineStart..<range.upperBound, spans: &spans)
            return
        }

        if parseTable(
            in: markdown,
            range: contentStart..<range.upperBound,
            nextLine: nextLine,
            spans: &spans
        ) {
            return
        }

        let inlineStart = parseLinePrefix(in: markdown, range: contentStart..<range.upperBound, spans: &spans)
        parseInlineMarkdown(in: markdown, range: inlineStart..<range.upperBound, spans: &spans)
    }

    private func parseHeading(
        in markdown: String,
        range: Range<String.Index>,
        spans: inout [MarkdownHighlightSpan]
    ) -> String.Index? {
        var current = range.lowerBound
        var count = 0

        while current < range.upperBound, markdown[current] == "#", count < 6 {
            count += 1
            current = markdown.index(after: current)
        }

        guard count > 0, current == range.upperBound || markdown[current].isWhitespace else {
            return nil
        }

        spans.append(MarkdownHighlightSpan(role: .headingMarker, range: range.lowerBound..<current))

        let textStart = skipSpaces(in: markdown, from: current, to: range.upperBound)
        if textStart < range.upperBound {
            spans.append(MarkdownHighlightSpan(role: .headingText(level: count), range: textStart..<range.upperBound))
        }

        return textStart
    }

    private func parseLinePrefix(
        in markdown: String,
        range: Range<String.Index>,
        spans: inout [MarkdownHighlightSpan]
    ) -> String.Index {
        guard range.lowerBound < range.upperBound else {
            return range.upperBound
        }

        if markdown[range.lowerBound] == ">" {
            let markerEnd = markdown.index(after: range.lowerBound)
            spans.append(MarkdownHighlightSpan(role: .quoteMarker, range: range.lowerBound..<markerEnd))
            let textStart = skipSpaces(in: markdown, from: markerEnd, to: range.upperBound)
            if textStart < range.upperBound {
                spans.append(MarkdownHighlightSpan(role: .quoteText, range: textStart..<range.upperBound))
            }
            return textStart
        }

        if let markerEnd = unorderedListMarkerEnd(in: markdown, range: range) {
            spans.append(MarkdownHighlightSpan(role: .listMarker, range: range.lowerBound..<markerEnd))
            return markerEnd
        }

        if let markerEnd = orderedListMarkerEnd(in: markdown, range: range) {
            spans.append(MarkdownHighlightSpan(role: .listMarker, range: range.lowerBound..<markerEnd))
            return markerEnd
        }

        return range.lowerBound
    }

    private func parseThematicBreak(
        in markdown: String,
        range: Range<String.Index>,
        spans: inout [MarkdownHighlightSpan]
    ) -> Bool {
        var current = range.lowerBound
        var marker: Character?
        var markerCount = 0

        while current < range.upperBound {
            let character = markdown[current]
            if character.isWhitespace {
                current = markdown.index(after: current)
                continue
            }

            guard character == "-" || character == "*" || character == "_" else {
                return false
            }

            if marker == nil {
                marker = character
            }

            guard marker == character else {
                return false
            }

            markerCount += 1
            current = markdown.index(after: current)
        }

        guard markerCount >= 3 else {
            return false
        }

        spans.append(MarkdownHighlightSpan(role: .thematicBreak, range: range))
        return true
    }
}

extension MarkdownSyntaxHighlighter {
    /// Walks inline syntax left-to-right so overlapping markers are consumed only once.
    private func parseInlineMarkdown(
        in markdown: String,
        range: Range<String.Index>,
        spans: inout [MarkdownHighlightSpan]
    ) {
        var current = range.lowerBound

        while current < range.upperBound {
            if let end = parseEscapedCharacter(in: markdown, at: current, limit: range.upperBound, spans: &spans) {
                current = end
            } else if let end = parseInlineCode(in: markdown, at: current, limit: range.upperBound, spans: &spans) {
                current = end
            } else if let end = parseLink(in: markdown, at: current, limit: range.upperBound, spans: &spans) {
                current = end
            } else if let end = parseStrong(in: markdown, at: current, limit: range.upperBound, spans: &spans) {
                current = end
            } else if let end = parseStrikethrough(in: markdown, at: current, limit: range.upperBound, spans: &spans) {
                current = end
            } else if let end = parseEmphasis(in: markdown, at: current, limit: range.upperBound, spans: &spans) {
                current = end
            } else {
                current = markdown.index(after: current)
            }
        }
    }

    /// Recognises an escaped punctuation pair before the escaped marker can open inline syntax.
    private func parseEscapedCharacter(
        in markdown: String,
        at index: String.Index,
        limit: String.Index,
        spans: inout [MarkdownHighlightSpan]
    ) -> String.Index? {
        guard markdown[index] == "\\" else {
            return nil
        }

        let escapedIndex = markdown.index(after: index)
        guard escapedIndex < limit, Self.escapableCharacters.contains(markdown[escapedIndex]) else {
            return nil
        }

        let end = markdown.index(after: escapedIndex)
        spans.append(MarkdownHighlightSpan(role: .escapedCharacter, range: index..<end))
        return end
    }

    /// Recognises a closed backtick pair and separates its markers from its content.
    private func parseInlineCode(
        in markdown: String,
        at index: String.Index,
        limit: String.Index,
        spans: inout [MarkdownHighlightSpan]
    ) -> String.Index? {
        guard markdown[index] == "`" else {
            return nil
        }

        let contentStart = markdown.index(after: index)
        guard let closing = firstIndex(of: "`", in: markdown, from: contentStart, to: limit) else {
            return nil
        }

        let end = markdown.index(after: closing)
        spans.append(MarkdownHighlightSpan(role: .inlineCodeMarker, range: index..<contentStart))
        if contentStart < closing {
            spans.append(MarkdownHighlightSpan(role: .inlineCodeText, range: contentStart..<closing))
        }
        spans.append(MarkdownHighlightSpan(role: .inlineCodeMarker, range: closing..<end))
        return end
    }

    /// Splits a Markdown link into marker, label, and destination spans.
    private func parseLink(
        in markdown: String,
        at index: String.Index,
        limit: String.Index,
        spans: inout [MarkdownHighlightSpan]
    ) -> String.Index? {
        guard markdown[index] == "[" else {
            return nil
        }

        let labelStart = markdown.index(after: index)
        var cursor = labelStart
        var labelEnd: String.Index?
        while cursor < limit {
            if markdown[cursor] == "[" {
                // Let the main scanner consider the nested opener instead of rescanning this suffix.
                return nil
            }
            if markdown[cursor] == "]" {
                labelEnd = cursor
                break
            }
            cursor = markdown.index(after: cursor)
        }
        guard let labelEnd else {
            return nil
        }

        let openParenthesis = markdown.index(after: labelEnd)
        guard openParenthesis < limit, markdown[openParenthesis] == "(" else {
            return nil
        }

        let destinationStart = markdown.index(after: openParenthesis)
        guard let destinationEnd = firstIndex(of: ")", in: markdown, from: destinationStart, to: limit) else {
            return nil
        }

        let end = markdown.index(after: destinationEnd)
        spans.append(MarkdownHighlightSpan(role: .linkMarker, range: index..<labelStart))
        spans.append(MarkdownHighlightSpan(role: .linkText, range: labelStart..<labelEnd))
        spans.append(MarkdownHighlightSpan(role: .linkMarker, range: labelEnd..<destinationStart))
        spans.append(MarkdownHighlightSpan(role: .linkDestination, range: destinationStart..<destinationEnd))
        spans.append(MarkdownHighlightSpan(role: .linkMarker, range: destinationEnd..<end))
        return end
    }

    /// Recognizes double-marker emphasis before the single-marker parser runs.
    private func parseStrong(
        in markdown: String,
        at index: String.Index,
        limit: String.Index,
        spans: inout [MarkdownHighlightSpan]
    ) -> String.Index? {
        guard let marker = doubleMarker(in: markdown, at: index, limit: limit) else {
            return nil
        }

        let textStart = markdown.index(index, offsetBy: 2)
        guard let closingStart = firstDoubleMarker(marker, in: markdown, from: textStart, to: limit) else {
            return nil
        }

        let end = markdown.index(closingStart, offsetBy: 2)
        spans.append(MarkdownHighlightSpan(role: .strongMarker, range: index..<textStart))
        spans.append(MarkdownHighlightSpan(role: .strongText, range: textStart..<closingStart))
        spans.append(MarkdownHighlightSpan(role: .strongMarker, range: closingStart..<end))
        return end
    }

    /// Recognises a closed GFM strikethrough pair and separates markers from content.
    private func parseStrikethrough(
        in markdown: String,
        at index: String.Index,
        limit: String.Index,
        spans: inout [MarkdownHighlightSpan]
    ) -> String.Index? {
        let second = markdown.index(after: index)
        guard second < limit, markdown[index] == "~", markdown[second] == "~" else {
            return nil
        }

        let textStart = markdown.index(index, offsetBy: 2)
        guard let closingStart = firstDoubleMarker("~", in: markdown, from: textStart, to: limit) else {
            return nil
        }

        let end = markdown.index(closingStart, offsetBy: 2)
        spans.append(MarkdownHighlightSpan(role: .strikethroughMarker, range: index..<textStart))
        spans.append(MarkdownHighlightSpan(role: .strikethroughText, range: textStart..<closingStart))
        spans.append(MarkdownHighlightSpan(role: .strikethroughMarker, range: closingStart..<end))
        return end
    }

    /// Recognizes simple single-marker emphasis without attempting full Markdown nesting.
    private func parseEmphasis(
        in markdown: String,
        at index: String.Index,
        limit: String.Index,
        spans: inout [MarkdownHighlightSpan]
    ) -> String.Index? {
        guard markdown[index] == "*" || markdown[index] == "_" else {
            return nil
        }

        let marker = markdown[index]
        let textStart = markdown.index(after: index)
        guard textStart < limit, markdown[textStart] != marker,
              let closing = firstIndex(of: marker, in: markdown, from: textStart, to: limit)
        else {
            return nil
        }

        let end = markdown.index(after: closing)
        spans.append(MarkdownHighlightSpan(role: .emphasisMarker, range: index..<textStart))
        spans.append(MarkdownHighlightSpan(role: .emphasisText, range: textStart..<closing))
        spans.append(MarkdownHighlightSpan(role: .emphasisMarker, range: closing..<end))
        return end
    }

    private func firstNonSpace(in markdown: String, range: Range<String.Index>) -> String.Index {
        var current = range.lowerBound

        while current < range.upperBound, markdown[current] == " " || markdown[current] == "\t" {
            current = markdown.index(after: current)
        }

        return current
    }

    private func lastNonSpace(in markdown: String, range: Range<String.Index>) -> String.Index {
        var current = range.upperBound

        while current > range.lowerBound {
            let previous = markdown.index(before: current)
            if markdown[previous] != " ", markdown[previous] != "\t" {
                break
            }
            current = previous
        }

        return current
    }

    private func skipSpaces(in markdown: String, from index: String.Index, to limit: String.Index) -> String.Index {
        var current = index

        while current < limit, markdown[current].isWhitespace {
            current = markdown.index(after: current)
        }

        return current
    }

    private func unorderedListMarkerEnd(in markdown: String, range: Range<String.Index>) -> String.Index? {
        let marker = markdown[range.lowerBound]
        guard marker == "-" || marker == "+" || marker == "*" else {
            return nil
        }

        let spaceIndex = markdown.index(after: range.lowerBound)
        guard spaceIndex < range.upperBound, markdown[spaceIndex].isWhitespace else {
            return nil
        }

        return markdown.index(after: spaceIndex)
    }

    private func orderedListMarkerEnd(in markdown: String, range: Range<String.Index>) -> String.Index? {
        var current = range.lowerBound

        while current < range.upperBound, markdown[current].isNumber {
            current = markdown.index(after: current)
        }

        guard current > range.lowerBound, current < range.upperBound,
              markdown[current] == "." || markdown[current] == ")"
        else {
            return nil
        }

        let spaceIndex = markdown.index(after: current)
        guard spaceIndex < range.upperBound, markdown[spaceIndex].isWhitespace else {
            return nil
        }

        return markdown.index(after: spaceIndex)
    }

    private func codeFenceMarkerEnd(
        in markdown: String,
        startingAt index: String.Index,
        lineEnd: String.Index
    ) -> String.Index? {
        guard index < lineEnd else {
            return nil
        }

        let marker = markdown[index]
        guard marker == "`" || marker == "~" else {
            return nil
        }

        var current = index
        var count = 0

        while current < lineEnd, markdown[current] == marker {
            count += 1
            current = markdown.index(after: current)
        }

        return count >= 3 ? current : nil
    }

    private func fenceLanguageIdentifierRange(
        in markdown: String,
        after markerEnd: String.Index,
        lineEnd: String.Index
    ) -> Range<String.Index>? {
        let languageStart = skipSpaces(in: markdown, from: markerEnd, to: lineEnd)
        guard languageStart < lineEnd else {
            return nil
        }

        var languageEnd = languageStart
        while languageEnd < lineEnd, !markdown[languageEnd].isWhitespace {
            languageEnd = markdown.index(after: languageEnd)
        }
        return languageStart..<languageEnd
    }

    private func fenceLanguage(
        in markdown: String,
        after markerEnd: String.Index,
        lineEnd: String.Index
    ) -> MarkdownCodeLanguage? {
        guard let range = fenceLanguageIdentifierRange(in: markdown, after: markerEnd, lineEnd: lineEnd) else {
            return nil
        }
        return MarkdownCodeLanguage(fenceTag: String(markdown[range]))
    }

    private func appendCodeSpans(
        in markdown: String,
        range: Range<String.Index>,
        language: MarkdownCodeLanguage?,
        spans: inout [MarkdownHighlightSpan]
    ) {
        guard let language else {
            return
        }

        let code = String(markdown[range])
        for span in MarkdownCodeSyntaxHighlighter().spans(in: code, language: language) {
            let lowerOffset = code.distance(from: code.startIndex, to: span.range.lowerBound)
            let upperOffset = code.distance(from: code.startIndex, to: span.range.upperBound)
            spans.append(
                MarkdownHighlightSpan(
                    role: MarkdownHighlightRole(codeRole: span.role),
                    range: markdown.index(range.lowerBound, offsetBy: lowerOffset)..<markdown.index(range.lowerBound, offsetBy: upperOffset)
                )
            )
        }
    }

    private func firstIndex(
        of character: Character,
        in markdown: String,
        from start: String.Index,
        to limit: String.Index
    ) -> String.Index? {
        var current = start

        while current < limit {
            if markdown[current] == character {
                return current
            }

            current = markdown.index(after: current)
        }

        return nil
    }

    private func doubleMarker(in markdown: String, at index: String.Index, limit: String.Index) -> Character? {
        let second = markdown.index(after: index)
        guard second < limit, markdown[index] == markdown[second],
              markdown[index] == "*" || markdown[index] == "_"
        else {
            return nil
        }

        return markdown[index]
    }

    private func firstDoubleMarker(
        _ marker: Character,
        in markdown: String,
        from start: String.Index,
        to limit: String.Index
    ) -> String.Index? {
        var current = start

        while current < limit {
            let next = markdown.index(after: current)
            if next < limit, markdown[current] == marker, markdown[next] == marker {
                return current
            }

            current = next
        }

        return nil
    }
}

private extension MarkdownSyntaxHighlighter {
    static let escapableCharacters = "\\`*{}_[]<>()#+-.!|~"
}

extension MarkdownSyntaxHighlighter {
    private func parseTable(
        in markdown: String,
        range: Range<String.Index>,
        nextLine: String?,
        spans: inout [MarkdownHighlightSpan]
    ) -> Bool {
        let content = String(markdown[range])

        if Self.isTableDelimiterRow(content) {
            spans.append(MarkdownHighlightSpan(role: .tableDelimiter, range: range))
            return true
        }

        guard Self.isTableRow(content) else {
            return false
        }

        let cellRole: MarkdownHighlightRole = Self.isTableDelimiterRow(nextLine ?? "") ? .tableHeader : .tableBody

        var current = range.lowerBound
        var cellStart = range.lowerBound

        while current < range.upperBound {
            if markdown[current] == "|", !isEscapedPipe(in: markdown, at: current, within: range) {
                spans.append(
                    MarkdownHighlightSpan(
                        role: .tableMarker,
                        range: current..<markdown.index(after: current)
                    )
                )
                if cellStart < current {
                    parseTableCell(in: markdown, range: cellStart..<current, role: cellRole, spans: &spans)
                }
                cellStart = markdown.index(after: current)
            }
            current = markdown.index(after: current)
        }

        if cellStart < range.upperBound {
            parseTableCell(in: markdown, range: cellStart..<range.upperBound, role: cellRole, spans: &spans)
        }

        return true
    }

    private func parseTableCell(
        in markdown: String,
        range: Range<String.Index>,
        role: MarkdownHighlightRole,
        spans: inout [MarkdownHighlightSpan]
    ) {
        let contentStart = firstNonSpace(in: markdown, range: range)
        guard contentStart < range.upperBound else {
            return
        }

        let contentEnd = lastNonSpace(in: markdown, range: contentStart..<range.upperBound)
        let contentRange = contentStart..<contentEnd

        spans.append(MarkdownHighlightSpan(role: role, range: contentRange))
        parseInlineMarkdown(in: markdown, range: contentRange, spans: &spans)
    }

    private func isEscapedPipe(
        in markdown: String,
        at index: String.Index,
        within range: Range<String.Index>
    ) -> Bool {
        var current = index
        var backslashCount = 0

        while current > range.lowerBound {
            let previous = markdown.index(before: current)
            guard markdown[previous] == "\\" else {
                break
            }
            backslashCount += 1
            current = previous
        }

        return !backslashCount.isMultiple(of: 2)
    }

    static func isTableDelimiterRow(_ line: String) -> Bool {
        let cells = delimiterCells(in: line)
        guard !cells.isEmpty else {
            return false
        }

        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            return trimmed.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }

    static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") else {
            return false
        }

        return trimmed.dropFirst().contains("|")
    }

    private static func delimiterCells(in line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var cells: [String] = []
        var current = ""

        for character in trimmed {
            if character == "|" {
                cells.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current)

        if cells.first?.isEmpty == true {
            cells.removeFirst()
        }
        if cells.last?.isEmpty == true {
            cells.removeLast()
        }

        return cells
    }
}

/// Holds the spans and fence transition produced while parsing one Markdown line.
struct MarkdownLineParseResult {
    let spans: [MarkdownHighlightSpan]
    let fenceStateAfter: MarkdownCodeFenceState

    var opensFence: Bool {
        fenceStateAfter.isInFence
    }
}

/// Tracks whether incremental Markdown parsing is currently inside a code fence.
struct MarkdownCodeFenceState: Equatable {
    let isInFence: Bool
    let language: MarkdownCodeLanguage?

    static let closed = MarkdownCodeFenceState(isInFence: false, language: nil)

    init(isInFence: Bool, language: MarkdownCodeLanguage? = nil) {
        self.isInFence = isInFence
        self.language = isInFence ? language : nil
    }
}
