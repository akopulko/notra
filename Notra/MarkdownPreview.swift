import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Renders parsed Markdown and overlays the selected note's hashtags and attachments.
struct MarkdownPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppearanceSettingKey.previewFontName) private var previewFontName = AppearanceFont.defaultName
    @AppStorage(AppearanceSettingKey.previewFixedWidthFontName) private var previewFixedWidthFontName =
        AppearanceFont.defaultName
    @AppStorage(AppearanceSettingKey.previewUsesEditorTheme) private var previewUsesEditorTheme = true
    // Keeps attachment presentation owned by the preview rather than by WebKit navigation.
    #if os(iOS)
    @State private var previewedAttachment: AttachmentPreviewItem?
    #endif

    let markdown: String
    let context: MarkdownRenderContext
    var tags: [NoteTag] = []
    let attachments: [TextBundleAsset]
    let toggleTask: (MarkdownTaskMarker, MarkdownTaskState) -> Void

    init(
        markdown: String,
        context: MarkdownRenderContext,
        tags: [NoteTag] = [],
        attachments: [TextBundleAsset] = [],
        toggleTask: @escaping (MarkdownTaskMarker, MarkdownTaskState) -> Void
    ) {
        self.markdown = markdown
        self.context = context
        self.tags = tags
        self.attachments = attachments
        self.toggleTask = toggleTask
    }

    var body: some View {
        let style = previewStyle
        MarkdownWebPreview(
            markdown: markdown,
            context: context,
            style: style,
            toggleTask: toggleTask
        )
        .overlay(alignment: .bottom) {
            PreviewMetadataOverlay(
                tags: tags,
                attachments: attachments,
                openAttachment: openAttachment
            )
            .padding(.horizontal, 16)
            .padding(.trailing, 4)
            .padding(.bottom, 12)
        }
        .environment(\.markdownStyle, style)
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
            previewFixedWidthFontName: previewFixedWidthFontName,
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

/// Selects linked non-image assets from the current Markdown body for the preview overlay.
enum PreviewAttachmentOverlayModel {
    nonisolated static func linkedNonImageAttachments(
        from attachments: [TextBundleAsset],
        markdown: String,
        noteURL: URL?
    ) -> [TextBundleAsset] {
        guard let noteURL else {
            return []
        }

        let assetBaseURL = noteURL.appendingPathComponent(
            TextBundleNoteRepository.assetsFolder,
            isDirectory: true
        )
        let linkedURLs = MarkdownAttachmentReferences.linkedURLs(
            in: markdown,
            assetBaseURL: assetBaseURL
        )
        return attachments
            .filter { attachment in
                attachment.kind == .attachment
                    && linkedURLs.contains(attachment.url.notraCanonicalFileURL)
            }
            .sorted {
                $0.filename.localizedStandardCompare($1.filename) == .orderedAscending
            }
    }
}

private struct PreviewMetadataOverlay: View {
    let tags: [NoteTag]
    let attachments: [TextBundleAsset]
    let openAttachment: (URL) -> Void

    var body: some View {
        if !tags.isEmpty || !attachments.isEmpty {
            HStack(alignment: .bottom, spacing: 12) {
                if !tags.isEmpty {
                    PreviewTagsOverlay(tags: tags)
                }
                if !tags.isEmpty, !attachments.isEmpty {
                    Spacer(minLength: 12)
                }
                if !attachments.isEmpty {
                    PreviewAttachmentsOverlay(
                        attachments: attachments,
                        openAttachment: openAttachment
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: tags.isEmpty ? .trailing : .leading)
        }
    }
}

private struct PreviewAttachmentsOverlay: View {
    @Environment(\.colorScheme) private var colorScheme

    let attachments: [TextBundleAsset]
    let openAttachment: (URL) -> Void

    var body: some View {
        let colors = MarkdownTheme.preferred(for: colorScheme).previewAttachmentColors
        return VStack(alignment: .trailing, spacing: 8) {
            ForEach(attachments) { attachment in
                Button {
                    openAttachment(attachment.url)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paperclip")
                        Text(attachment.filename)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(colors.foregroundColor)
                    .background(
                        colors.backgroundColor.opacity(colorScheme == .dark ? 0.73 : 0.87),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(
                                Color.white.opacity(colorScheme == .dark ? 0.24 : 0.3),
                                lineWidth: 0.5
                            )
                    }
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.26 : 0.14),
                        radius: 5,
                        y: 1
                    )
                    .frame(maxWidth: 220, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Attachment \(attachment.filename)")
            }
        }
        .padding(.vertical, 4)
    }
}

enum PreviewTagDisplay {
    nonisolated static func text(for tag: NoteTag, maxNameCharacters: Int = 15) -> String {
        guard tag.name.count > maxNameCharacters else {
            return tag.prefixedDisplayName
        }
        return "#\(tag.name.prefix(maxNameCharacters))..."
    }
}

/// Displays note tags in the preview without changing the Markdown document itself.
private struct PreviewTagsOverlay: View {
    let tags: [NoteTag]

    var body: some View {
        TagFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(tags) { tag in
                TagCapsule(
                    tag: tag,
                    size: .compact,
                    style: .previewOverlay,
                    displayText: PreviewTagDisplay.text(for: tag)
                )
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
