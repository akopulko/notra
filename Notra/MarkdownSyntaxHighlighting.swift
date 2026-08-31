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

/// Semantic Markdown roles used to apply editor syntax colors.
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
    case codeComment
    case codeKeyword
    case codeString
    case codeNumber
    case codeType
    case codeFunction
    case codeOperator
    case codeTag
    case codeAttribute
}

/// Associates a syntax role with a UTF-16 range in the Markdown source.
struct MarkdownHighlightSpan: Equatable {
    let role: MarkdownHighlightRole
    let range: Range<String.Index>
}

/// Stores light and dark colors for one syntax role.
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

/// Theme-derived colours for tag UI, keeping tag styling tied to the syntax palette.
struct MarkdownTagColors: Equatable {
    let background: MarkdownSyntaxColor
    let foreground: MarkdownSyntaxColor

    static let neutral = MarkdownTagColors(
        background: MarkdownSyntaxColor(hex: "#6B7280"),
        foreground: MarkdownSyntaxColor(hex: "#D1D5DB")
    )

    var backgroundColor: Color {
        background.color
    }

    var foregroundColor: Color {
        foreground.color
    }
}

/// Bundles syntax colors and provides the theme selected by the current color scheme.
struct MarkdownHighlightTheme: Equatable {
    let marker: MarkdownSyntaxColor
    let heading: MarkdownSyntaxColor
    let emphasis: MarkdownSyntaxColor
    let code: MarkdownSyntaxColor
    let quote: MarkdownSyntaxColor
    let link: MarkdownSyntaxColor
    let table: MarkdownSyntaxColor
    let codeComment: MarkdownSyntaxColor
    let codeKeyword: MarkdownSyntaxColor
    let codeString: MarkdownSyntaxColor
    let codeNumber: MarkdownSyntaxColor
    let codeType: MarkdownSyntaxColor
    let codeFunction: MarkdownSyntaxColor
    let codeOperator: MarkdownSyntaxColor
    let codeTag: MarkdownSyntaxColor
    let codeAttribute: MarkdownSyntaxColor

    static let tokyoNight = MarkdownHighlightTheme(
        marker: MarkdownSyntaxColor(hex: "#565F89"),
        heading: MarkdownSyntaxColor(hex: "#7AA2F7"),
        emphasis: MarkdownSyntaxColor(hex: "#BB9AF7"),
        code: MarkdownSyntaxColor(hex: "#9ECE6A"),
        quote: MarkdownSyntaxColor(hex: "#E0AF68"),
        link: MarkdownSyntaxColor(hex: "#2AC3DE"),
        table: MarkdownSyntaxColor(hex: "#0DB9D7"),
        codeComment: MarkdownSyntaxColor(hex: "#565F89"),
        codeKeyword: MarkdownSyntaxColor(hex: "#BB9AF7"),
        codeString: MarkdownSyntaxColor(hex: "#9ECE6A"),
        codeNumber: MarkdownSyntaxColor(hex: "#FF9E64"),
        codeType: MarkdownSyntaxColor(hex: "#2AC3DE"),
        codeFunction: MarkdownSyntaxColor(hex: "#7DCFFF"),
        codeOperator: MarkdownSyntaxColor(hex: "#89DDFF"),
        codeTag: MarkdownSyntaxColor(hex: "#7AA2F7"),
        codeAttribute: MarkdownSyntaxColor(hex: "#E0AF68")
    )

    static let light = MarkdownHighlightTheme(
        marker: MarkdownSyntaxColor(hex: "#6B7280"),
        heading: MarkdownSyntaxColor(hex: "#1D4ED8"),
        emphasis: MarkdownSyntaxColor(hex: "#7C3AED"),
        code: MarkdownSyntaxColor(hex: "#047857"),
        quote: MarkdownSyntaxColor(hex: "#B45309"),
        link: MarkdownSyntaxColor(hex: "#0369A1"),
        table: MarkdownSyntaxColor(hex: "#0E7490"),
        codeComment: MarkdownSyntaxColor(hex: "#6B7280"),
        codeKeyword: MarkdownSyntaxColor(hex: "#7C3AED"),
        codeString: MarkdownSyntaxColor(hex: "#047857"),
        codeNumber: MarkdownSyntaxColor(hex: "#C2410C"),
        codeType: MarkdownSyntaxColor(hex: "#0369A1"),
        codeFunction: MarkdownSyntaxColor(hex: "#0E7490"),
        codeOperator: MarkdownSyntaxColor(hex: "#0891B2"),
        codeTag: MarkdownSyntaxColor(hex: "#1D4ED8"),
        codeAttribute: MarkdownSyntaxColor(hex: "#B45309")
    )

    /// Selects the dark or light palette without making the editor own theme state.
    static func preferred(for colorScheme: ColorScheme) -> MarkdownHighlightTheme {
        switch colorScheme {
        case .dark:
            tokyoNight
        default:
            light
        }
    }

    func tagColors(for colorScheme: ColorScheme) -> MarkdownTagColors {
        MarkdownTagColors(
            background: code,
            foreground: colorScheme == .dark
                ? MarkdownSyntaxColor(hex: "#293F1A")
                : MarkdownSyntaxColor(hex: "#FFFFFF")
        )
    }

    var noteListTitleColor: Color {
        noteListTitleSyntaxColor.color
    }

    var noteListTitleSyntaxColor: MarkdownSyntaxColor {
        heading
    }

    /// Maps a Markdown role to its palette color, delegating fenced-code roles to `codeColor`.
    func color(for role: MarkdownHighlightRole) -> MarkdownSyntaxColor {
        if let codeRole = role.codeRole {
            return codeColor(for: codeRole)
        }

        return switch role {
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
        case .codeComment, .codeKeyword, .codeString, .codeNumber, .codeType, .codeFunction, .codeOperator, .codeTag, .codeAttribute:
            marker
        }
    }

    /// Maps language-token roles to the dedicated code palette entries.
    func codeColor(for role: MarkdownCodeHighlightRole) -> MarkdownSyntaxColor {
        switch role {
        case .comment: codeComment
        case .keyword: codeKeyword
        case .string: codeString
        case .number: codeNumber
        case .type: codeType
        case .function: codeFunction
        case .operator: codeOperator
        case .tag: codeTag
        case .attribute: codeAttribute
        }
    }
}

/// Parses Markdown line-by-line into stable spans suitable for native text views.
struct MarkdownSyntaxHighlighter {
    /// Converts syntax spans into an attributed string for SwiftUI preview or native text views.
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

        if isCodeFence(in: markdown, startingAt: contentStart, lineEnd: range.upperBound) {
            spans.append(MarkdownHighlightSpan(role: .codeFence, range: contentStart..<range.upperBound))
            fenceState = fenceState.isInFence
                ? .closed
                : MarkdownCodeFenceState(
                    isInFence: true,
                    language: fenceLanguage(in: markdown, startingAt: contentStart, lineEnd: range.upperBound)
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
    /// Walks inline syntax left-to-right so overlapping markers are consumed only once.
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

    /// Recognizes a closed backtick pair and marks the complete inline-code range.
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
        spans.append(MarkdownHighlightSpan(role: .emphasisMarker, range: index..<textStart))
        spans.append(MarkdownHighlightSpan(role: .emphasisText, range: textStart..<closingStart))
        spans.append(MarkdownHighlightSpan(role: .emphasisMarker, range: closingStart..<end))
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

    private func fenceLanguage(in markdown: String, startingAt index: String.Index, lineEnd: String.Index) -> MarkdownCodeLanguage? {
        let marker = markdown[index]
        var current = index
        while current < lineEnd, markdown[current] == marker {
            current = markdown.index(after: current)
        }
        let tag = String(markdown[current..<lineEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)
        return tag.flatMap(MarkdownCodeLanguage.init(fenceTag:))
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

private extension MarkdownHighlightRole {
    var codeRole: MarkdownCodeHighlightRole? {
        switch self {
        case .codeComment: .comment
        case .codeKeyword: .keyword
        case .codeString: .string
        case .codeNumber: .number
        case .codeType: .type
        case .codeFunction: .function
        case .codeOperator: .operator
        case .codeTag: .tag
        case .codeAttribute: .attribute
        default: nil
        }
    }

    init(codeRole: MarkdownCodeHighlightRole) {
        switch codeRole {
        case .comment: self = .codeComment
        case .keyword: self = .codeKeyword
        case .string: self = .codeString
        case .number: self = .codeNumber
        case .type: self = .codeType
        case .function: self = .codeFunction
        case .operator: self = .codeOperator
        case .tag: self = .codeTag
        case .attribute: self = .codeAttribute
        }
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

/// Stores a syntax span using the offset unit expected by UITextView and NSTextView.
struct MarkdownUTF16Span: Equatable {
    let role: MarkdownHighlightRole
    let lower: Int
    let upper: Int
}

/// Describes the native text replacement that produced the newest editor string.
struct MarkdownTextEdit {
    let range: NSRange
    let replacementUTF16Length: Int
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

        var fenceState = MarkdownCodeFenceState.closed
        for line in oldCache.prefix(prefix) {
            fenceState = line.fenceStateAfter
        }

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

        var fenceState = MarkdownCodeFenceState.closed
        for line in oldCache.prefix(parseStart) {
            fenceState = line.fenceStateAfter
        }

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
