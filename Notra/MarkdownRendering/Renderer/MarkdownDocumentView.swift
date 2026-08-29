import CoreGraphics
import SwiftUI

/// Renders the document block tree while preserving stable identities for async content.
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

    /// Uses an eager document for export and the cancellable model for interactive preview.
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

    /// Applies the input context to the shared block-content renderer.
    private func documentContent(_ document: NotraMarkdownDocument) -> some View {
        MarkdownDocumentContentView(
            document: document,
            context: input.context,
            mode: input.mode,
            preloadedImages: preloadedImages
        )
    }
}

/// Hosts the document's blocks and keeps PDF pagination decisions local to export rendering.
private struct MarkdownDocumentContentView: View {
    @Environment(\.markdownStyle) private var style

    let document: NotraMarkdownDocument
    let context: MarkdownRenderContext
    let mode: MarkdownRenderMode
    let preloadedImages: [URL: CGImage]

    /// Switches from lazy interactive rows to eager PDF rows so pagination sees every block.
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

    /// Passes flattened row metadata to each block so indentation and spacing stay deterministic.
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
                usesCompactParagraphSpacing: row.usesCompactParagraphSpacing,
                usesListTrailingParagraphSpacing: row.usesListTrailingParagraphSpacing
            )
        }
    }
}
