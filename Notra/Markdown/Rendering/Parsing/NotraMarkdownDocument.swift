import Foundation

/// Stores the parsed block tree consumed by the HTML preview and PDF renderer.
struct NotraMarkdownDocument: Equatable, Sendable {
    let blocks: [MarkdownBlock]
}

/// The block-level Markdown forms preserved in the renderer-owned document.
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
    /// The exact Markdown marker rendered as this task checkbox, when source coordinates are available.
    let taskMarker: MarkdownTaskMarker?
    let blocks: [MarkdownBlock]
}

/// The checked state of a GitHub-style task-list item.
enum MarkdownTaskState: Equatable, Sendable {
    case checked
    case unchecked
}

/// Identifies a task marker by its one-based UTF-8 source position.
struct MarkdownTaskMarker: Equatable, Sendable {
    let line: Int
    let column: Int
    let state: MarkdownTaskState
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

/// The optional left, center, or right alignment declared by a GFM table separator.
enum MarkdownTableAlignment: Equatable, Sendable {
    case leading
    case center
    case trailing
}
