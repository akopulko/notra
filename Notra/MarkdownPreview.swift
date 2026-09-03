import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Renders parsed Markdown and overlays the selected note's hashtags.
struct MarkdownPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppearanceSettingKey.previewFontName) private var previewFontName = AppearanceFont.defaultName
    @AppStorage(AppearanceSettingKey.previewUsesEditorTheme) private var previewUsesEditorTheme = true
    // Keeps attachment presentation owned by the preview rather than by WebKit navigation.
    #if os(iOS)
    @State private var previewedAttachment: AttachmentPreviewItem?
    #endif

    let markdown: String
    let context: MarkdownRenderContext
    var tags: [NoteTag] = []

    var body: some View {
        MarkdownWebPreview(
            markdown: markdown,
            context: context,
            style: previewStyle,
            openAttachment: openAttachment
        )
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
        #if os(iOS)
        .sheet(item: $previewedAttachment) { item in
            AttachmentPreviewController(item: item)
        }
        #endif
    }

    private var previewStyle: MarkdownStyle {
        .notra(
            previewFontName: previewFontName,
            // Preview themes are limited to Markdown text colours; the scroll canvas stays system-owned.
            theme: previewTheme
        )
    }

    private var previewTheme: MarkdownTheme? {
        previewUsesEditorTheme ? MarkdownTheme.preferred(for: colorScheme) : nil
    }

    /// Keeps local attachment activation consistent with the previous native preview.
    private func openAttachment(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        previewedAttachment = AttachmentPreviewItem(url: url)
        #endif
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
