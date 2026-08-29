import SwiftUI

/// Lays out normalized Markdown table rows with measured columns and alignment rules.
struct MarkdownTableView: View {
    @Environment(\.markdownStyle) private var style

    let table: MarkdownTable
    let context: MarkdownRenderContext
    var mode: MarkdownRenderMode = .preview
    var preloadedImages: [URL: CGImage] = [:]

    /// Uses an eager grid for PDF and a horizontally scrollable grid for interactive preview.
    var body: some View {
        if columnCount > 0 {
            Group {
                if mode == .pdf {
                    tableGrid
                } else {
                    ScrollView(.horizontal) {
                        tableGrid
                    }
                }
            }
            .padding(.bottom, style.paragraphSpacing)
        }
    }

    /// Builds the shared header/body grid with one measured width per column.
    private var tableGrid: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            headerRow
            bodyRows
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(.rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(style.borderColor, lineWidth: 1)
        }
    }

    private var headerRow: some View {
        GridRow {
            ForEach(0..<columnCount, id: \.self) { column in
                cellView(
                    inlines: table.header[safe: column]?.inlines ?? [],
                    column: column,
                    isHeader: true,
                    isLastColumn: column == columnCount - 1,
                    isLastRow: table.rows.isEmpty
                )
            }
        }
    }

    private var bodyRows: some View {
        ForEach(Array(table.rows.enumerated()), id: \.element.id) { rowOffset, row in
            GridRow {
                ForEach(0..<columnCount, id: \.self) { column in
                    cellView(
                        inlines: row.cells[safe: column]?.inlines ?? [],
                        column: column,
                        isHeader: false,
                        isLastColumn: column == columnCount - 1,
                        isLastRow: rowOffset == table.rows.count - 1
                    )
                }
            }
        }
    }

    /// Pads short rows to the table's maximum column count before layout.
    private var columnCount: Int {
        max(table.header.count, table.rows.map { $0.cells.count }.max() ?? 0)
    }

    /// Renders one cell with header styling, source-order content, and column alignment.
    private func cellView(
        inlines: [MarkdownInline],
        column: Int,
        isHeader: Bool,
        isLastColumn: Bool,
        isLastRow: Bool
    ) -> some View {
        MarkdownInlineContentView(
            inlines: inlines,
            context: context,
            mode: mode,
            preloadedImages: preloadedImages
        )
        .fontWeight(isHeader ? .semibold : .regular)
        .padding(style.tableCellPadding)
        .frame(
            minWidth: mode == .pdf ? 0 : 96,
            maxWidth: .infinity,
            alignment: alignment(for: column)
        )
        .fixedSize(horizontal: false, vertical: true)
        .background(backgroundColor(isHeader: isHeader))
        .overlay(alignment: .trailing) {
            if !isLastColumn {
                style.borderColor.frame(width: 1)
            }
        }
        .overlay(alignment: .bottom) {
            if !isLastRow {
                style.borderColor.frame(height: 1)
            }
        }
    }

    private func backgroundColor(isHeader: Bool) -> some View {
        if isHeader {
            return (mode == .pdf ? BackgroundFill.printable : BackgroundFill.thin).view
        }

        return BackgroundFill.clear.view
    }

    /// Converts the parsed alignment declaration into SwiftUI's grid alignment.
    private func alignment(for column: Int) -> Alignment {
        guard column < table.columnAlignments.count else {
            return .leading
        }

        switch table.columnAlignments[column] {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }

        return self[index]
    }
}
