import SwiftUI

/// Renders parsed Markdown and overlays the selected note's tags when preview mode allows it.
struct MarkdownPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppearanceSettingKey.previewFontName) private var previewFontName = AppearanceFont.defaultName
    @AppStorage(AppearanceSettingKey.previewUsesEditorTheme) private var previewUsesEditorTheme = true

    let markdown: String
    let context: MarkdownRenderContext
    var tags: [NoteTag] = []

    var body: some View {
        ScrollView {
            MarkdownDocumentView(
                input: MarkdownRenderInput(
                    markdown: markdown,
                    context: context
                )
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .padding(.bottom, tags.isEmpty ? 0 : 88)
        }
        .overlay(alignment: .bottom) {
            if !tags.isEmpty {
                PreviewTagsOverlay(tags: tags)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .environment(\.markdownStyle, previewStyle)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Note preview")
    }

    private var previewStyle: MarkdownStyle {
        .notra(
            previewFontName: previewFontName,
            // Preview themes are limited to Markdown text colours; the scroll canvas stays system-owned.
            theme: previewUsesEditorTheme ? MarkdownHighlightTheme.preferred(for: colorScheme) : nil
        )
    }
}

/// Displays note tags in the preview without changing the Markdown document itself.
private struct PreviewTagsOverlay: View {
    let tags: [NoteTag]

    var body: some View {
        TagFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(tags) { tag in
                TagCapsule(tag: tag, size: .compact, style: .previewOverlay)
                    .frame(maxWidth: 180)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Note tags")
    }
}
