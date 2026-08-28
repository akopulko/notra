import Foundation
import Markdown

struct SwiftMarkdownParser {
    private let extendedAutolinkParser: GFMExtendedAutolinkParser
    private let tableParser: GFMTableBlockParser

    nonisolated init(
        extendedAutolinkParser: GFMExtendedAutolinkParser = GFMExtendedAutolinkParser(),
        tableParser: GFMTableBlockParser = GFMTableBlockParser()
    ) {
        self.extendedAutolinkParser = extendedAutolinkParser
        self.tableParser = tableParser
    }

    nonisolated func parse(_ markdown: String) -> NotraMarkdownDocument {
        if let document = tableParser.parse(markdown, swiftParser: self) {
            return document
        }

        return parseSwiftMarkdown(markdown, path: "document")
    }

    nonisolated func parseSwiftMarkdown(_ markdown: String, path: String) -> NotraMarkdownDocument {
        let document = Document(parsing: markdown)
        return NotraMarkdownDocument(
            blocks: blocks(in: document, path: path),
            compactParagraphIDs: compactParagraphIDs(in: document, path: path),
            spacedListIDs: spacedListIDs(in: document, path: path)
        )
    }

    private nonisolated func compactParagraphIDs(in document: Document, path: String) -> Set<String> {
        let children = Array(document.children)
        var result: Set<String> = []

        for offset in children.indices.dropLast() {
            guard children[offset] is Paragraph,
                  children[offset + 1] is UnorderedList || children[offset + 1] is OrderedList,
                  let paragraphRange = children[offset].range,
                  let listRange = children[offset + 1].range,
                  listRange.lowerBound.line == paragraphRange.upperBound.line + 1
            else {
                continue
            }

            result.insert("\(path).\(offset)")
        }

        return result
    }

    private nonisolated func spacedListIDs(in document: Document, path: String) -> Set<String> {
        let children = Array(document.children)
        var result: Set<String> = []

        for offset in children.indices.dropLast() {
            guard children[offset] is UnorderedList || children[offset] is OrderedList,
                  children[offset + 1] is Paragraph
            else {
                continue
            }

            result.insert("\(path).\(offset)")
        }

        return result
    }

    private nonisolated func blocks(in markup: any Markup, path: String) -> [MarkdownBlock] {
        markup.children.enumerated().compactMap { offset, child in
            block(from: child, path: "\(path).\(offset)")
        }
    }

    private nonisolated func block(from markup: any Markup, path: String) -> MarkdownBlock? {
        if let htmlBlock = markup as? HTMLBlock {
            return .paragraph(id: path, [.text(htmlBlock.rawHTML)])
        }

        if let paragraph = markup as? Paragraph {
            return .paragraph(id: path, inlines(in: paragraph, path: path))
        }

        if let heading = markup as? Heading {
            return .heading(id: path, level: heading.level, inlines(in: heading, path: path))
        }

        if let unorderedList = markup as? UnorderedList {
            return .unorderedList(id: path, items: listItems(in: unorderedList, path: path))
        }

        if let orderedList = markup as? OrderedList {
            return .orderedList(
                id: path,
                start: Int(orderedList.startIndex),
                items: listItems(in: orderedList, path: path)
            )
        }

        if let blockQuote = markup as? BlockQuote {
            return .blockQuote(id: path, blocks: blocks(in: blockQuote, path: path))
        }

        if let codeBlock = markup as? CodeBlock {
            return .codeBlock(id: path, language: codeBlock.language, code: codeBlock.code)
        }

        if markup is ThematicBreak {
            return .horizontalRule(id: path)
        }

        if let table = markup as? Table {
            return .table(id: path, tableModel(from: table, path: path))
        }

        let fallback = inlines(in: markup, path: path)
        return fallback.isEmpty ? nil : .paragraph(id: path, fallback)
    }

    private nonisolated func listItems(in list: any Markup, path: String) -> [MarkdownListItem] {
        list.children.enumerated().compactMap { offset, child in
            guard let item = child as? ListItem else {
                return nil
            }

            return MarkdownListItem(
                id: "\(path).item.\(offset)",
                taskState: taskState(for: item.checkbox),
                blocks: blocks(in: item, path: "\(path).item.\(offset)")
            )
        }
    }

    private nonisolated func taskState(for checkbox: Checkbox?) -> MarkdownTaskState? {
        switch checkbox {
        case .checked:
            .checked
        case .unchecked:
            .unchecked
        case nil:
            nil
        }
    }

    private nonisolated func tableModel(from table: Table, path: String) -> MarkdownTable {
        MarkdownTable(
            columnAlignments: table.columnAlignments.map(tableAlignment),
            header: cells(in: table.head, path: "\(path).header"),
            rows: table.body.rows.enumerated().map { offset, row in
                MarkdownTableRow(
                    id: "\(path).row.\(offset)",
                    cells: cells(in: row, path: "\(path).row.\(offset)")
                )
            }
        )
    }

    private nonisolated func tableAlignment(_ alignment: Table.ColumnAlignment?) -> MarkdownTableAlignment {
        switch alignment {
        case .left, nil:
            return .leading
        case .center:
            return .center
        case .right:
            return .trailing
        @unknown default:
            return .leading
        }
    }

    private nonisolated func cells(in row: some TableCellContainer, path: String) -> [MarkdownTableCell] {
        row.cells.enumerated().map { offset, cell in
            MarkdownTableCell(
                id: "\(path).cell.\(offset)",
                inlines: inlines(in: cell, path: "\(path).cell.\(offset)")
            )
        }
    }

    private nonisolated func inlines(in markup: any Markup, path: String) -> [MarkdownInline] {
        markup.children.enumerated().flatMap { offset, child in
            inline(from: child, path: "\(path).inline.\(offset)")
        }
    }

    private nonisolated func inline(from markup: any Markup, path: String) -> [MarkdownInline] {
        if let text = markup as? Markdown.Text {
            return extendedAutolinkParser.parse(text.string)
        }

        if let strong = markup as? Strong {
            return [.strong(inlines(in: strong, path: path))]
        }

        if let emphasis = markup as? Emphasis {
            return [.emphasis(inlines(in: emphasis, path: path))]
        }

        if let strikethrough = markup as? Strikethrough {
            return [.strikethrough(inlines(in: strikethrough, path: path))]
        }

        if let inlineCode = markup as? InlineCode {
            return [.code(inlineCode.code)]
        }

        if let link = markup as? Markdown.Link, let destination = link.destination {
            return [
                .link(
                    destination: destination,
                    title: link.title,
                    children: inlines(in: link, path: path)
                )
            ]
        }

        if let image = markup as? Markdown.Image {
            return [
                .image(
                    source: image.source,
                    title: image.title,
                    alt: plainText(in: image)
                )
            ]
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
        return fallback.isEmpty ? [] : extendedAutolinkParser.parse(fallback)
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
}
