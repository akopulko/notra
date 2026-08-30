import Foundation

/// Stores the parsed block tree consumed by the native Markdown renderer.
struct NotraMarkdownDocument: Equatable, Sendable {
    let blocks: [MarkdownBlock]
    let compactParagraphIDs: Set<String>
    let spacedListIDs: Set<String>
    let renderRows: [MarkdownRenderRow]

    nonisolated init(
        blocks: [MarkdownBlock],
        compactParagraphIDs: Set<String> = [],
        spacedListIDs: Set<String> = []
    ) {
        self.blocks = blocks
        self.compactParagraphIDs = compactParagraphIDs
        self.spacedListIDs = spacedListIDs
        renderRows = MarkdownRenderRowBuilder.rows(
            from: blocks,
            compactParagraphIDs: compactParagraphIDs,
            spacedListIDs: spacedListIDs
        )
    }
}

/// The block-level Markdown forms that the renderer lays out vertically.
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

/// Inline Markdown content preserved inside paragraphs, headings, table cells, and list items.
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

/// A list item with its inline content and any nested list blocks.
struct MarkdownListItem: Equatable, Identifiable, Sendable {
    let id: String
    let taskState: MarkdownTaskState?
    let blocks: [MarkdownBlock]
}

/// The checked state of a GitHub-style task-list item.
enum MarkdownTaskState: Equatable, Sendable {
    case checked
    case unchecked
}

/// A normalized table with alignment metadata and renderable rows.
struct MarkdownTable: Equatable, Sendable {
    let columnAlignments: [MarkdownTableAlignment]
    let header: [MarkdownTableCell]
    let rows: [MarkdownTableRow]
}

/// One table row, including a stable ID for SwiftUI's repeated row views.
struct MarkdownTableRow: Equatable, Identifiable, Sendable {
    let id: String
    let cells: [MarkdownTableCell]
}

/// One table cell's inline content and stable render identity.
struct MarkdownTableCell: Equatable, Identifiable, Sendable {
    let id: String
    let inlines: [MarkdownInline]
}

/// Describes whether a list row is unordered, ordered, or a task marker.
enum MarkdownListMarker: Equatable, Sendable {
    case unordered(Int)
    case ordered(Int)
    case task(MarkdownTaskState)
}

/// Flattens nested list content into the indented rows used by the renderer.
struct MarkdownRenderRow: Equatable, Identifiable, Sendable {
    let id: String
    let block: MarkdownBlock
    let nestingLevel: Int
    let marker: MarkdownListMarker?
    let quoteDepth: Int
    let isInsideListItem: Bool
    let usesCompactParagraphSpacing: Bool
    let usesListTrailingParagraphSpacing: Bool
}

private enum MarkdownRenderRowBuilder {
    private struct RenderingContext {
        let nestingLevel: Int
        let quoteDepth: Int
        let isInsideListItem: Bool
        let compactParagraphIDs: Set<String>
        let spacedListIDs: Set<String>
    }

    nonisolated static func rows(
        from blocks: [MarkdownBlock],
        compactParagraphIDs: Set<String>,
        spacedListIDs: Set<String>
    ) -> [MarkdownRenderRow] {
        var rows: [MarkdownRenderRow] = []
        append(
            blocks,
            to: &rows,
            context: RenderingContext(
                nestingLevel: 0,
                quoteDepth: 0,
                isInsideListItem: false,
                compactParagraphIDs: compactParagraphIDs,
                spacedListIDs: spacedListIDs
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
            case let .unorderedList(id, items):
                let firstRowIndex = rows.count
                append(
                    items,
                    to: &rows,
                    context: context,
                    orderedStart: nil
                )
                applyTrailingParagraphSpacing(
                    to: &rows,
                    after: firstRowIndex,
                    if: context.spacedListIDs.contains(id)
                )
            case let .orderedList(id, start, items):
                let firstRowIndex = rows.count
                append(
                    items,
                    to: &rows,
                    context: context,
                    orderedStart: start
                )
                applyTrailingParagraphSpacing(
                    to: &rows,
                    after: firstRowIndex,
                    if: context.spacedListIDs.contains(id)
                )
            case let .blockQuote(_, blocks):
                append(
                    blocks,
                    to: &rows,
                    context: RenderingContext(
                        nestingLevel: context.nestingLevel,
                        quoteDepth: context.quoteDepth + 1,
                        isInsideListItem: context.isInsideListItem,
                        compactParagraphIDs: context.compactParagraphIDs,
                        spacedListIDs: context.spacedListIDs
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
                            && context.compactParagraphIDs.contains(block.id),
                        usesListTrailingParagraphSpacing: false
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
                    compactParagraphIDs: context.compactParagraphIDs,
                    spacedListIDs: context.spacedListIDs
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
                usesCompactParagraphSpacing: firstRow.usesCompactParagraphSpacing,
                usesListTrailingParagraphSpacing: firstRow.usesListTrailingParagraphSpacing
            )
        }
    }

    private nonisolated static func applyTrailingParagraphSpacing(
        to rows: inout [MarkdownRenderRow],
        after firstRowIndex: Int,
        if shouldApply: Bool
    ) {
        guard shouldApply, firstRowIndex < rows.count else {
            return
        }

        let lastRowIndex = rows.index(before: rows.endIndex)
        let lastRow = rows[lastRowIndex]
        rows[lastRowIndex] = MarkdownRenderRow(
            id: lastRow.id,
            block: lastRow.block,
            nestingLevel: lastRow.nestingLevel,
            marker: lastRow.marker,
            quoteDepth: lastRow.quoteDepth,
            isInsideListItem: lastRow.isInsideListItem,
            usesCompactParagraphSpacing: lastRow.usesCompactParagraphSpacing,
            usesListTrailingParagraphSpacing: true
        )
    }
}

/// The optional left, center, or right alignment declared by a GFM table separator.
enum MarkdownTableAlignment: Equatable, Sendable {
    case leading
    case center
    case trailing
}
