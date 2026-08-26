import SwiftUI

struct MarkdownDocumentView: View {
    @Environment(\.markdownStyle) private var style
    @State private var model = MarkdownPreviewModel()

    let input: MarkdownRenderInput

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                EmptyView()
            case let .parsed(document):
                MarkdownDocumentContentView(
                    document: document,
                    context: input.context
                )
            }
        }
        .font(style.bodyFont)
        .foregroundStyle(style.textColor)
        .textSelection(.enabled)
        .task(id: input) {
            model.update(markdown: input.markdown)
        }
    }
}

private struct MarkdownDocumentContentView: View {
    @Environment(\.markdownStyle) private var style

    let document: NotraMarkdownDocument
    let context: MarkdownRenderContext

    var body: some View {
        LazyVStack(alignment: .leading, spacing: style.blockSpacing) {
            ForEach(document.renderRows) { row in
                MarkdownBlockView(
                    block: row.block,
                    context: context,
                    nestingLevel: row.nestingLevel,
                    marker: row.marker,
                    quoteDepth: row.quoteDepth,
                    isInsideListItem: row.isInsideListItem
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
