import CoreGraphics
import SwiftUI

struct MarkdownDocumentView: View {
    @Environment(\.markdownStyle) private var style
    @State private var model = MarkdownPreviewModel()

    let input: MarkdownRenderInput
    let eagerDocument: NotraMarkdownDocument?
    let preloadedImages: [URL: CGImage]

    init(
        input: MarkdownRenderInput,
        eagerDocument: NotraMarkdownDocument? = nil,
        preloadedImages: [URL: CGImage] = [:]
    ) {
        self.input = input
        self.eagerDocument = eagerDocument
        self.preloadedImages = preloadedImages
    }

    var body: some View {
        Group {
            if let eagerDocument {
                documentContent(eagerDocument)
            } else {
                switch model.state {
                case .idle:
                    EmptyView()
                case let .parsed(document):
                    documentContent(document)
                }
            }
        }
        .font(style.bodyFont)
        .foregroundStyle(style.textColor)
        .textSelection(.enabled)
        .task(id: input) {
            guard eagerDocument == nil else {
                return
            }
            model.update(markdown: input.markdown)
        }
    }

    private func documentContent(_ document: NotraMarkdownDocument) -> some View {
        MarkdownDocumentContentView(
            document: document,
            context: input.context,
            mode: input.mode,
            preloadedImages: preloadedImages
        )
    }
}

private struct MarkdownDocumentContentView: View {
    @Environment(\.markdownStyle) private var style

    let document: NotraMarkdownDocument
    let context: MarkdownRenderContext
    let mode: MarkdownRenderMode
    let preloadedImages: [URL: CGImage]

    var body: some View {
        Group {
            if mode == .pdf {
                VStack(alignment: .leading, spacing: style.blockSpacing) {
                    rows
                }
            } else {
                LazyVStack(alignment: .leading, spacing: style.blockSpacing) {
                    rows
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rows: some View {
        ForEach(document.renderRows) { row in
            MarkdownBlockView(
                block: row.block,
                context: context,
                mode: mode,
                preloadedImages: preloadedImages,
                nestingLevel: row.nestingLevel,
                marker: row.marker,
                quoteDepth: row.quoteDepth,
                isInsideListItem: row.isInsideListItem,
                usesCompactParagraphSpacing: row.usesCompactParagraphSpacing
            )
        }
    }
}
