import SwiftUI

struct MarkdownBlockView: View {
    @Environment(\.markdownStyle) private var style

    let block: MarkdownBlock
    let context: MarkdownRenderContext
    let nestingLevel: Int
    let marker: MarkdownListMarker?
    let quoteDepth: Int
    var isInsideListItem = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isInsideListItem {
                markerView
                    .frame(width: style.listMarkerWidth, alignment: .trailing)
                    .foregroundStyle(style.markerColor)
            }

            leafBlock
        }
        .padding(.leading, contentLeadingPadding)
        .foregroundStyle(quoteDepth > 0 ? style.secondaryTextColor : style.textColor)
        .overlay(alignment: .leading) {
            if quoteDepth > 0 {
                HStack(spacing: 4) {
                    ForEach(0..<quoteDepth, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(style.quoteAccentColor)
                            .frame(width: 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var leafBlock: some View {
        switch block {
        case let .paragraph(_, inlines):
            MarkdownInlineContentView(inlines: inlines, context: context)
                .padding(.bottom, paragraphBottomSpacing)
        case let .heading(_, level, inlines):
            heading(level: level, inlines: inlines)
        case let .codeBlock(_, language, code):
            CodeBlockView(language: language, code: code)
        case let .table(_, table):
            MarkdownTableView(table: table, context: context)
        case .horizontalRule:
            Divider()
                .overlay(style.dividerColor)
                .padding(.bottom, style.paragraphSpacing)
        case .unorderedList, .orderedList, .blockQuote:
            EmptyView()
        }
    }

    private func heading(level: Int, inlines: [MarkdownInline]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MarkdownInlineContentView(inlines: inlines, context: context)
                .font(style.headingFont(level: level))
                .fontWeight(.semibold)
                .foregroundStyle(style.headingColor)

            if level <= 2 {
                Divider()
                    .overlay(style.dividerColor)
            }
        }
        .padding(.top, level <= 2 ? 24 : 16)
        .padding(.bottom, style.paragraphSpacing)
    }

    private var paragraphBottomSpacing: CGFloat {
        isInsideListItem ? style.listItemParagraphSpacing : style.paragraphSpacing
    }

    private var contentLeadingPadding: CGFloat {
        CGFloat(quoteDepth) * 16 + (nestingLevel == 0 ? 0 : style.listIndent)
    }

    @ViewBuilder
    private var markerView: some View {
        switch marker {
        case let .some(.unordered(level)):
            Text(unorderedMarker(for: level))
        case let .some(.ordered(value)):
            Text("\(value).")
        case .some(.task(.checked)):
            Image(systemName: "checkmark.square")
        case .some(.task(.unchecked)):
            Image(systemName: "square")
        case nil:
            Color.clear
        }
    }

    private func unorderedMarker(for level: Int) -> String {
        switch level % 3 {
        case 1:
            "○"
        case 2:
            "▪"
        default:
            "•"
        }
    }
}

private struct CodeBlockView: View {
    @Environment(\.markdownStyle) private var style
    @Environment(\.secondaryBackgroundFill) private var secondaryBackgroundFill

    let language: String?
    let code: String

    var body: some View {
        ScrollView(.horizontal) {
            Text(code)
                .font(style.codeBlockFont)
                .foregroundStyle(style.codeTextColor)
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(secondaryBackgroundFill.view)
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityLabel(accessibilityLabel)
        .padding(.bottom, style.paragraphSpacing)
    }

    private var accessibilityLabel: String {
        if let language, !language.isEmpty {
            return "Code block, \(language)"
        }

        return "Code block"
    }
}
