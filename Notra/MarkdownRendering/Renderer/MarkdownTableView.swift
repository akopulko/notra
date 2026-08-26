import SwiftUI

struct MarkdownTableView: View {
    @Environment(\.markdownStyle) private var style

    let table: MarkdownTable
    let context: MarkdownRenderContext

    var body: some View {
        if columnCount > 0 {
            ScrollView(.horizontal) {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    headerRow
                    bodyRows
                }
                .clipShape(.rect(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(style.borderColor, lineWidth: 1)
                }
            }
            .padding(.bottom, style.paragraphSpacing)
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

    private var columnCount: Int {
        max(table.header.count, table.rows.map { $0.cells.count }.max() ?? 0)
    }

    private func cellView(
        inlines: [MarkdownInline],
        column: Int,
        isHeader: Bool,
        isLastColumn: Bool,
        isLastRow: Bool
    ) -> some View {
        MarkdownInlineContentView(inlines: inlines, context: context)
            .fontWeight(isHeader ? .semibold : .regular)
            .padding(style.tableCellPadding)
            .frame(minWidth: 96, maxWidth: .infinity, alignment: alignment(for: column))
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
            return BackgroundFill.thin.view
        }

        return BackgroundFill.clear.view
    }

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
