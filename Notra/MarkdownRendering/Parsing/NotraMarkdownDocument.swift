import Foundation

protocol MarkdownParsing: Sendable {
    nonisolated func parse(_ markdown: String) -> NotraMarkdownDocument
}

struct NotraMarkdownDocument: Equatable, Sendable {
    let blocks: [MarkdownBlock]
    let renderRows: [MarkdownRenderRow]

    nonisolated init(blocks: [MarkdownBlock]) {
        self.blocks = blocks
        renderRows = MarkdownRenderRowBuilder.rows(from: blocks)
    }
}

enum MarkdownBlock: Equatable, Identifiable, Sendable {
    case paragraph(id: String, [MarkdownInline])
    case heading(id: String, level: Int, [MarkdownInline])
    case unorderedList(id: String, items: [MarkdownListItem])
    case orderedList(id: String, start: Int, items: [MarkdownListItem])
    case blockQuote(id: String, blocks: [MarkdownBlock])
    case codeBlock(id: String, language: String?, code: String)
    case table(id: String, MarkdownTable)
    case horizontalRule(id: String)

    nonisolated var id: String {
        switch self {
        case let .paragraph(id, _),
             let .heading(id, _, _),
             let .unorderedList(id, _),
             let .orderedList(id, _, _),
             let .blockQuote(id, _),
             let .codeBlock(id, _, _),
             let .table(id, _),
             let .horizontalRule(id):
            id
        }
    }
}

enum MarkdownInline: Equatable, Sendable {
    case text(String)
    case strong([MarkdownInline])
    case emphasis([MarkdownInline])
    case strikethrough([MarkdownInline])
    case code(String)
    case link(destination: String, title: String?, children: [MarkdownInline])
    case image(source: String?, title: String?, alt: String)
    case softBreak
    case lineBreak
}

struct MarkdownListItem: Equatable, Identifiable, Sendable {
    let id: String
    let taskState: MarkdownTaskState?
    let blocks: [MarkdownBlock]
}

enum MarkdownTaskState: Equatable, Sendable {
    case checked
    case unchecked
}

struct MarkdownTable: Equatable, Sendable {
    let columnAlignments: [MarkdownTableAlignment]
    let header: [MarkdownTableCell]
    let rows: [MarkdownTableRow]
}

struct MarkdownTableRow: Equatable, Identifiable, Sendable {
    let id: String
    let cells: [MarkdownTableCell]
}

struct MarkdownTableCell: Equatable, Identifiable, Sendable {
    let id: String
    let inlines: [MarkdownInline]
}

enum MarkdownListMarker: Equatable, Sendable {
    case unordered(Int)
    case ordered(Int)
    case task(MarkdownTaskState)
}

struct MarkdownRenderRow: Equatable, Identifiable, Sendable {
    let id: String
    let block: MarkdownBlock
    let nestingLevel: Int
    let marker: MarkdownListMarker?
    let quoteDepth: Int
    let isInsideListItem: Bool
}

private enum MarkdownRenderRowBuilder {
    nonisolated static func rows(from blocks: [MarkdownBlock]) -> [MarkdownRenderRow] {
        var rows: [MarkdownRenderRow] = []
        append(
            blocks,
            to: &rows,
            nestingLevel: 0,
            quoteDepth: 0,
            isInsideListItem: false
        )
        return rows
    }

    private nonisolated static func append(
        _ blocks: [MarkdownBlock],
        to rows: inout [MarkdownRenderRow],
        nestingLevel: Int,
        quoteDepth: Int,
        isInsideListItem: Bool
    ) {
        for block in blocks {
            switch block {
            case let .unorderedList(_, items):
                append(
                    items,
                    to: &rows,
                    nestingLevel: nestingLevel + (isInsideListItem ? 1 : 0),
                    quoteDepth: quoteDepth,
                    orderedStart: nil
                )
            case let .orderedList(_, start, items):
                append(
                    items,
                    to: &rows,
                    nestingLevel: nestingLevel + (isInsideListItem ? 1 : 0),
                    quoteDepth: quoteDepth,
                    orderedStart: start
                )
            case let .blockQuote(_, blocks):
                append(
                    blocks,
                    to: &rows,
                    nestingLevel: nestingLevel,
                    quoteDepth: quoteDepth + 1,
                    isInsideListItem: isInsideListItem
                )
            default:
                rows.append(
                    MarkdownRenderRow(
                        id: block.id,
                        block: block,
                        nestingLevel: nestingLevel,
                        marker: nil,
                        quoteDepth: quoteDepth,
                        isInsideListItem: isInsideListItem
                    )
                )
            }
        }
    }

    private nonisolated static func append(
        _ items: [MarkdownListItem],
        to rows: inout [MarkdownRenderRow],
        nestingLevel: Int,
        quoteDepth: Int,
        orderedStart: Int?
    ) {
        for (offset, item) in items.enumerated() {
            let marker: MarkdownListMarker = if let taskState = item.taskState {
                .task(taskState)
            } else if let orderedStart {
                .ordered(orderedStart + offset)
            } else {
                .unordered(nestingLevel)
            }

            let firstRowIndex = rows.count
            append(
                item.blocks,
                to: &rows,
                nestingLevel: nestingLevel,
                quoteDepth: quoteDepth,
                isInsideListItem: true
            )

            guard firstRowIndex < rows.count else {
                continue
            }

            let firstRow = rows[firstRowIndex]
            rows[firstRowIndex] = MarkdownRenderRow(
                id: firstRow.id,
                block: firstRow.block,
                nestingLevel: firstRow.nestingLevel,
                marker: marker,
                quoteDepth: firstRow.quoteDepth,
                isInsideListItem: firstRow.isInsideListItem
            )
        }
    }
}

enum MarkdownTableAlignment: Equatable, Sendable {
    case leading
    case center
    case trailing
}
