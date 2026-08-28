import Foundation

protocol MarkdownParsing: Sendable {
    nonisolated func parse(_ markdown: String) -> NotraMarkdownDocument
}

struct NotraMarkdownDocument: Equatable, Sendable {
    let blocks: [MarkdownBlock]
    let compactParagraphIDs: Set<String>
    let renderRows: [MarkdownRenderRow]

    nonisolated init(blocks: [MarkdownBlock], compactParagraphIDs: Set<String> = []) {
        self.blocks = blocks
        self.compactParagraphIDs = compactParagraphIDs
        renderRows = MarkdownRenderRowBuilder.rows(
            from: blocks,
            compactParagraphIDs: compactParagraphIDs
        )
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
    let usesCompactParagraphSpacing: Bool
}

private enum MarkdownRenderRowBuilder {
    private struct RenderingContext {
        let nestingLevel: Int
        let quoteDepth: Int
        let isInsideListItem: Bool
        let compactParagraphIDs: Set<String>
    }

    nonisolated static func rows(
        from blocks: [MarkdownBlock],
        compactParagraphIDs: Set<String>
    ) -> [MarkdownRenderRow] {
        var rows: [MarkdownRenderRow] = []
        append(
            blocks,
            to: &rows,
            context: RenderingContext(
                nestingLevel: 0,
                quoteDepth: 0,
                isInsideListItem: false,
                compactParagraphIDs: compactParagraphIDs
            )
        )
        return rows
    }

    private nonisolated static func append(
        _ blocks: [MarkdownBlock],
        to rows: inout [MarkdownRenderRow],
        context: RenderingContext
    ) {
        for block in blocks {
            switch block {
            case let .unorderedList(_, items):
                append(
                    items,
                    to: &rows,
                    context: context,
                    orderedStart: nil
                )
            case let .orderedList(_, start, items):
                append(
                    items,
                    to: &rows,
                    context: context,
                    orderedStart: start
                )
            case let .blockQuote(_, blocks):
                append(
                    blocks,
                    to: &rows,
                    context: RenderingContext(
                        nestingLevel: context.nestingLevel,
                        quoteDepth: context.quoteDepth + 1,
                        isInsideListItem: context.isInsideListItem,
                        compactParagraphIDs: context.compactParagraphIDs
                    )
                )
            default:
                rows.append(
                    MarkdownRenderRow(
                        id: block.id,
                        block: block,
                        nestingLevel: context.nestingLevel,
                        marker: nil,
                        quoteDepth: context.quoteDepth,
                        isInsideListItem: context.isInsideListItem,
                        usesCompactParagraphSpacing: !context.isInsideListItem
                            && context.compactParagraphIDs.contains(block.id)
                    )
                )
            }
        }
    }

    private nonisolated static func append(
        _ items: [MarkdownListItem],
        to rows: inout [MarkdownRenderRow],
        context: RenderingContext,
        orderedStart: Int?
    ) {
        for (offset, item) in items.enumerated() {
            let marker: MarkdownListMarker = if let taskState = item.taskState {
                .task(taskState)
            } else if let orderedStart {
                .ordered(orderedStart + offset)
            } else {
                .unordered(context.nestingLevel + (context.isInsideListItem ? 1 : 0))
            }

            let firstRowIndex = rows.count
            append(
                item.blocks,
                to: &rows,
                context: RenderingContext(
                    nestingLevel: context.nestingLevel + (context.isInsideListItem ? 1 : 0),
                    quoteDepth: context.quoteDepth,
                    isInsideListItem: true,
                    compactParagraphIDs: context.compactParagraphIDs
                )
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
                isInsideListItem: firstRow.isInsideListItem,
                usesCompactParagraphSpacing: firstRow.usesCompactParagraphSpacing
            )
        }
    }
}

enum MarkdownTableAlignment: Equatable, Sendable {
    case leading
    case center
    case trailing
}
