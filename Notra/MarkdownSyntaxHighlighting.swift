// swiftlint:disable file_length
import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

#if os(macOS)
typealias MarkdownPlatformColor = NSColor
typealias MarkdownPlatformFont = NSFont
#elseif os(iOS)
typealias MarkdownPlatformColor = UIColor
typealias MarkdownPlatformFont = UIFont
#endif

extension MarkdownPlatformColor {
    static var defaultLabel: MarkdownPlatformColor {
        #if os(macOS)
        return .labelColor
        #else
        return .label
        #endif
    }
}

enum MarkdownHighlightRole: Equatable {
    case headingMarker
    case headingText
    case emphasisMarker
    case emphasisText
    case inlineCode
    case codeFence
    case quoteMarker
    case listMarker
    case linkText
    case linkDestination
    case linkMarker
    case thematicBreak
    case tableMarker
    case tableHeader
    case tableDelimiter
    case tableBody
}

struct MarkdownHighlightSpan: Equatable {
    let role: MarkdownHighlightRole
    let range: Range<String.Index>
}

struct MarkdownSyntaxColor: Equatable {
    let hex: String

    private var components: (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let integer = Int(value, radix: 16) else {
            return nil
        }

        return (
            red: CGFloat((integer >> 16) & 0xFF) / 255.0,
            green: CGFloat((integer >> 8) & 0xFF) / 255.0,
            blue: CGFloat(integer & 0xFF) / 255.0
        )
    }

    var color: Color {
        guard let components else {
            return .primary
        }

        return Color(
            red: Double(components.red),
            green: Double(components.green),
            blue: Double(components.blue)
        )
    }

    var platformColor: MarkdownPlatformColor {
        guard let components else {
            return .defaultLabel
        }

        return MarkdownPlatformColor(
            red: components.red,
            green: components.green,
            blue: components.blue,
            alpha: 1
        )
    }
}

struct MarkdownHighlightTheme: Equatable {
    let marker: MarkdownSyntaxColor
    let heading: MarkdownSyntaxColor
    let emphasis: MarkdownSyntaxColor
    let code: MarkdownSyntaxColor
    let quote: MarkdownSyntaxColor
    let link: MarkdownSyntaxColor
    let table: MarkdownSyntaxColor

    static let tokyoNight = MarkdownHighlightTheme(
        marker: MarkdownSyntaxColor(hex: "#565F89"),
        heading: MarkdownSyntaxColor(hex: "#7AA2F7"),
        emphasis: MarkdownSyntaxColor(hex: "#BB9AF7"),
        code: MarkdownSyntaxColor(hex: "#9ECE6A"),
        quote: MarkdownSyntaxColor(hex: "#E0AF68"),
        link: MarkdownSyntaxColor(hex: "#2AC3DE"),
        table: MarkdownSyntaxColor(hex: "#0DB9D7")
    )

    static let light = MarkdownHighlightTheme(
        marker: MarkdownSyntaxColor(hex: "#6B7280"),
        heading: MarkdownSyntaxColor(hex: "#1D4ED8"),
        emphasis: MarkdownSyntaxColor(hex: "#7C3AED"),
        code: MarkdownSyntaxColor(hex: "#047857"),
        quote: MarkdownSyntaxColor(hex: "#B45309"),
        link: MarkdownSyntaxColor(hex: "#0369A1"),
        table: MarkdownSyntaxColor(hex: "#0E7490")
    )

    static func preferred(for colorScheme: ColorScheme) -> MarkdownHighlightTheme {
        switch colorScheme {
        case .dark:
            tokyoNight
        default:
            light
        }
    }

    func color(for role: MarkdownHighlightRole) -> MarkdownSyntaxColor {
        switch role {
        case .headingMarker, .linkMarker, .thematicBreak:
            marker
        case .headingText:
            heading
        case .emphasisMarker:
            marker
        case .emphasisText:
            emphasis
        case .inlineCode, .codeFence:
            code
        case .quoteMarker:
            quote
        case .listMarker:
            marker
        case .linkText, .linkDestination:
            link
        case .tableHeader:
            heading
        case .tableMarker, .tableDelimiter, .tableBody:
            table
        }
    }
}

struct MarkdownSyntaxHighlighter {
    func highlight(_ markdown: String, theme: MarkdownHighlightTheme) -> AttributedString {
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

    func spans(in markdown: String) -> [MarkdownHighlightSpan] {
        var spans: [MarkdownHighlightSpan] = []
        var lineStart = markdown.startIndex
        var isInFence = false

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
                isInFence: &isInFence,
                nextLine: nextLine,
                spans: &spans
            )

            lineStart = nextLineStart
        }

        return spans
    }

    func parseLine(_ line: String, isInFence: Bool, nextLine: String? = nil) -> MarkdownLineParseResult {
        var spans: [MarkdownHighlightSpan] = []
        var inFence = isInFence
        parseLine(
            line,
            range: line.startIndex..<line.endIndex,
            isInFence: &inFence,
            nextLine: nextLine,
            spans: &spans
        )
        return MarkdownLineParseResult(spans: spans, opensFence: inFence != isInFence)
    }

    private func parseLine(
        _ markdown: String,
        range: Range<String.Index>,
        isInFence: inout Bool,
        nextLine: String?,
        spans: inout [MarkdownHighlightSpan]
    ) {
        let contentStart = firstNonSpace(in: markdown, range: range)

        if isCodeFence(in: markdown, startingAt: contentStart, lineEnd: range.upperBound) {
            spans.append(MarkdownHighlightSpan(role: .codeFence, range: contentStart..<range.upperBound))
            isInFence.toggle()
            return
        }

        guard !isInFence else {
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
            spans.append(MarkdownHighlightSpan(role: .headingText, range: textStart..<range.upperBound))
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
            return skipSpaces(in: markdown, from: markerEnd, to: range.upperBound)
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
    private func parseInlineMarkdown(
        in markdown: String,
        range: Range<String.Index>,
        spans: inout [MarkdownHighlightSpan]
    ) {
        var current = range.lowerBound

        while current < range.upperBound {
            if let end = parseInlineCode(in: markdown, at: current, limit: range.upperBound, spans: &spans) {
                current = end
            } else if let end = parseLink(in: markdown, at: current, limit: range.upperBound, spans: &spans) {
                current = end
            } else if let end = parseStrong(in: markdown, at: current, limit: range.upperBound, spans: &spans) {
                current = end
            } else if let end = parseEmphasis(in: markdown, at: current, limit: range.upperBound, spans: &spans) {
                current = end
            } else {
                current = markdown.index(after: current)
            }
        }
    }

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
        spans.append(MarkdownHighlightSpan(role: .inlineCode, range: index..<end))
        return end
    }

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
        guard let labelEnd = firstIndex(of: "]", in: markdown, from: labelStart, to: limit) else {
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
        spans.append(MarkdownHighlightSpan(role: .emphasisMarker, range: index..<textStart))
        spans.append(MarkdownHighlightSpan(role: .emphasisText, range: textStart..<closingStart))
        spans.append(MarkdownHighlightSpan(role: .emphasisMarker, range: closingStart..<end))
        return end
    }

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

    private func isCodeFence(in markdown: String, startingAt index: String.Index, lineEnd: String.Index) -> Bool {
        guard index < lineEnd else {
            return false
        }

        let marker = markdown[index]
        guard marker == "`" || marker == "~" else {
            return false
        }

        var current = index
        var count = 0

        while current < lineEnd, markdown[current] == marker {
            count += 1
            current = markdown.index(after: current)
        }

        return count >= 3
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

struct MarkdownLineParseResult {
    let spans: [MarkdownHighlightSpan]
    let opensFence: Bool
}

struct MarkdownUTF16Span: Equatable {
    let role: MarkdownHighlightRole
    let lower: Int
    let upper: Int
}

struct MarkdownLineHighlight {
    let range: Range<Int>
    let spans: [MarkdownUTF16Span]
    let opensFence: Bool
    let isInFence: Bool
}

struct MarkdownHighlightCache {
    private(set) var text = ""
    private(set) var lines: [MarkdownLineHighlight] = []

    var count: Int {
        lines.count
    }

    var isEmpty: Bool {
        lines.isEmpty
    }

    mutating func setText(_ newText: String) {
        text = newText
        lines = Self.buildLines(for: newText)
    }

    @discardableResult
    mutating func updateText(_ newText: String) -> Range<Int>? {
        guard newText != text else {
            return nil
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

        var parity = false
        for line in oldCache.prefix(prefix) where line.opensFence {
            parity.toggle()
        }

        var updatedLines = Array(oldCache.prefix(prefix))
        var changedRange = prefix..<prefix + changedCount
        let highlighter = MarkdownSyntaxHighlighter()

        for index in 0..<changedCount {
            let entryIndex = prefix + index
            Self.appendParsedLine(
                entry: newEntries[entryIndex],
                highlighter: highlighter,
                parity: &parity,
                nextLine: newEntries.count > entryIndex + 1 ? newEntries[entryIndex + 1].content : nil,
                into: &updatedLines
            )
        }

        for index in 0..<suffix {
            let newLineIndex = newEntries.count - suffix + index
            let oldLineIndex = oldCache.count - suffix + index
            guard parity != oldCache[oldLineIndex].isInFence else {
                break
            }
            Self.appendParsedLine(
                entry: newEntries[newLineIndex],
                highlighter: highlighter,
                parity: &parity,
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
                    opensFence: oldLine.opensFence,
                    isInFence: oldLine.isInFence
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
        theme: MarkdownHighlightTheme,
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
        parity: inout Bool,
        nextLine: String?,
        into lines: inout [MarkdownLineHighlight]
    ) {
        let parsed = highlighter.parseLine(entry.content, isInFence: parity, nextLine: nextLine)
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
                opensFence: parsed.opensFence,
                isInFence: parity
            )
        )
        if parsed.opensFence {
            parity.toggle()
        }
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
        var isInFence = false
        let highlighter = MarkdownSyntaxHighlighter()
        let entries = lineEntries(for: text)

        for (index, entry) in entries.enumerated() {
            let nextLine = entries.count > index + 1 ? entries[index + 1].content : nil
            let parsed = highlighter.parseLine(entry.content, isInFence: isInFence, nextLine: nextLine)
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
                    opensFence: parsed.opensFence,
                    isInFence: isInFence
                )
            )
            if parsed.opensFence {
                isInFence.toggle()
            }
        }

        return lines
    }
}
