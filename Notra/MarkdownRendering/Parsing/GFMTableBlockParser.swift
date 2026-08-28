import Foundation
import Markdown

struct GFMTableBlockParser: Sendable {
    private enum Segment {
        case markdown(String)
        case table([String])

        nonisolated var isTable: Bool {
            if case .table = self {
                return true
            }
            return false
        }
    }

    private struct ParsedDelimiter {
        let alignments: [MarkdownTableAlignment]
    }

    private let inlineParser: GFMExtendedAutolinkParser

    nonisolated init(inlineParser: GFMExtendedAutolinkParser = GFMExtendedAutolinkParser()) {
        self.inlineParser = inlineParser
    }

    nonisolated func parse(_ markdown: String, swiftParser: SwiftMarkdownParser) -> NotraMarkdownDocument? {
        let segments = segments(in: markdown)
        guard segments.contains(where: \.isTable) else {
            return nil
        }

        var blocks: [MarkdownBlock] = []
        var compactParagraphIDs: Set<String> = []

        for (offset, segment) in segments.enumerated() {
            switch segment {
            case let .markdown(markdown):
                let path = segments.count == 1 ? "document" : "document.segment.\(offset)"
                let document = swiftParser.parseSwiftMarkdown(markdown, path: path)
                blocks.append(contentsOf: document.blocks)
                compactParagraphIDs.formUnion(document.compactParagraphIDs)
            case let .table(lines):
                guard let table = table(from: lines, path: "document.segment.\(offset)") else {
                    let document = swiftParser.parseSwiftMarkdown(
                        lines.joined(separator: "\n"),
                        path: "document.segment.\(offset)"
                    )
                    blocks.append(contentsOf: document.blocks)
                    compactParagraphIDs.formUnion(document.compactParagraphIDs)
                    continue
                }

                blocks.append(.table(id: "document.segment.\(offset)", table))
            }
        }

        return NotraMarkdownDocument(
            blocks: blocks,
            compactParagraphIDs: compactParagraphIDs
        )
    }

    private nonisolated func segments(in markdown: String) -> [Segment] {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var segments: [Segment] = []
        var markdownLines: [String] = []
        var index = 0
        var isInFencedCode = false

        while index < lines.count {
            let line = lines[index]
            if isFenceLine(line) {
                isInFencedCode.toggle()
            }

            if !isInFencedCode, index + 1 < lines.count, isPotentialTableHeader(line), let delimiter = delimiter(in: lines[index + 1]) {
                let headerCells = cells(in: line)
                if headerCells.count == delimiter.alignments.count {
                    flushMarkdownLines(&markdownLines, into: &segments)
                    var tableLines = [line, lines[index + 1]]
                    index += 2

                    while index < lines.count, isPotentialTableBodyRow(lines[index]) {
                        tableLines.append(lines[index])
                        index += 1
                    }

                    segments.append(.table(tableLines))
                    continue
                }
            }

            markdownLines.append(line)
            index += 1
        }

        flushMarkdownLines(&markdownLines, into: &segments)
        return segments
    }

    private nonisolated func flushMarkdownLines(_ lines: inout [String], into segments: inout [Segment]) {
        guard !lines.isEmpty else {
            return
        }

        let markdown = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
        if !markdown.isEmpty {
            segments.append(.markdown(markdown))
        }
        lines.removeAll()
    }

    private nonisolated func table(from lines: [String], path: String) -> MarkdownTable? {
        guard lines.count >= 2, let delimiter = delimiter(in: lines[1]) else {
            return nil
        }

        let headerCells = cells(in: lines[0])
        guard headerCells.count == delimiter.alignments.count else {
            return nil
        }

        let columnCount = headerCells.count
        return MarkdownTable(
            columnAlignments: delimiter.alignments,
            header: headerCells.enumerated().map { offset, cell in
                MarkdownTableCell(id: "\(path).header.cell.\(offset)", inlines: inlines(from: cell, path: "\(path).header.cell.\(offset)"))
            },
            rows: lines.dropFirst(2).enumerated().map { rowOffset, line in
                MarkdownTableRow(
                    id: "\(path).row.\(rowOffset)",
                    cells: normalizedCells(cells(in: line), columnCount: columnCount).enumerated().map { cellOffset, cell in
                        MarkdownTableCell(
                            id: "\(path).row.\(rowOffset).cell.\(cellOffset)",
                            inlines: inlines(from: cell, path: "\(path).row.\(rowOffset).cell.\(cellOffset)")
                        )
                    }
                )
            }
        )
    }

    private nonisolated func normalizedCells(_ cells: [String], columnCount: Int) -> [String] {
        if cells.count >= columnCount {
            return Array(cells.prefix(columnCount))
        }

        return cells + Array(repeating: "", count: columnCount - cells.count)
    }

    private nonisolated func delimiter(in line: String) -> ParsedDelimiter? {
        let cells = cells(in: line)
        guard !cells.isEmpty else {
            return nil
        }

        var alignments: [MarkdownTableAlignment] = []
        for cell in cells {
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard trimmed.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil else {
                return nil
            }

            if trimmed.hasPrefix(":"), trimmed.hasSuffix(":") {
                alignments.append(.center)
            } else if trimmed.hasSuffix(":") {
                alignments.append(.trailing)
            } else {
                alignments.append(.leading)
            }
        }

        return ParsedDelimiter(alignments: alignments)
    }

    private nonisolated func cells(in line: String) -> [String] {
        var row = line
        if hasUnescapedPipePrefix(row) {
            row.removeFirst()
        }
        if hasUnescapedPipeSuffix(row) {
            row.removeLast()
        }

        var cells: [String] = []
        var current = ""
        var backtickRunLength = 0
        var openCodeRunLength: Int?
        var previousWasEscape = false

        for character in row {
            if character == "`", !previousWasEscape {
                backtickRunLength += 1
                current.append(character)
                continue
            }

            if backtickRunLength > 0 {
                if openCodeRunLength == backtickRunLength {
                    openCodeRunLength = nil
                } else if openCodeRunLength == nil {
                    openCodeRunLength = backtickRunLength
                }
                backtickRunLength = 0
            }

            if character == "|", openCodeRunLength == nil, !previousWasEscape {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current.removeAll()
            } else {
                current.append(character)
            }

            previousWasEscape = character == "\\" && !previousWasEscape
            if character != "\\" {
                previousWasEscape = false
            }
        }

        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private nonisolated func inlines(from markdown: String, path: String) -> [MarkdownInline] {
        let document = Document(parsing: markdown)
        if let paragraph = document.children.first(where: { _ in true }) as? Paragraph {
            return paragraph.children.enumerated().flatMap { offset, child in
                inline(from: child, path: "\(path).inline.\(offset)")
            }
        }

        return inlineParser.parse(markdown)
    }

    private nonisolated func inline(from markup: any Markup, path: String) -> [MarkdownInline] {
        if let text = markup as? Markdown.Text {
            return inlineParser.parse(text.string)
        }

        if let strong = markup as? Strong {
            return [.strong(inlines(from: strong, path: path))]
        }

        if let emphasis = markup as? Emphasis {
            return [.emphasis(inlines(from: emphasis, path: path))]
        }

        if let strikethrough = markup as? Strikethrough {
            return [.strikethrough(inlines(from: strikethrough, path: path))]
        }

        if let inlineCode = markup as? InlineCode {
            return [.code(inlineCode.code)]
        }

        if let link = markup as? Markdown.Link, let destination = link.destination {
            return [.link(destination: destination, title: link.title, children: inlines(from: link, path: path))]
        }

        if let image = markup as? Markdown.Image {
            return [.image(source: image.source, title: image.title, alt: plainText(in: image))]
        }

        if markup is SoftBreak {
            return [.softBreak]
        }

        if markup is LineBreak {
            return [.lineBreak]
        }

        if let inlineHTML = markup as? InlineHTML {
            return [.text(inlineHTML.rawHTML)]
        }

        let fallback = plainText(in: markup)
        return fallback.isEmpty ? [] : inlineParser.parse(fallback)
    }

    private nonisolated func inlines(from markup: any Markup, path: String) -> [MarkdownInline] {
        markup.children.enumerated().flatMap { offset, child in
            inline(from: child, path: "\(path).inline.\(offset)")
        }
    }

    private nonisolated func plainText(in markup: any Markup) -> String {
        markup.children.map { child in
            if let text = child as? Markdown.Text {
                return text.string
            }
            return plainText(in: child)
        }
        .joined()
    }

    private nonisolated func isPotentialTableHeader(_ line: String) -> Bool {
        line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private nonisolated func isPotentialTableBodyRow(_ line: String) -> Bool {
        line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private nonisolated func isFenceLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    private nonisolated func hasUnescapedPipePrefix(_ row: String) -> Bool {
        row.first == "|"
    }

    private nonisolated func hasUnescapedPipeSuffix(_ row: String) -> Bool {
        guard row.last == "|" else {
            return false
        }

        var backslashCount = 0
        for character in row.dropLast().reversed() {
            if character == "\\" {
                backslashCount += 1
            } else {
                break
            }
        }

        return backslashCount.isMultiple(of: 2)
    }
}
