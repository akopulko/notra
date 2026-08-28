import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct MarkdownInlineContentView: View {
    @Environment(\.markdownStyle) private var style

    let inlines: [MarkdownInline]
    let context: MarkdownRenderContext
    let mode: MarkdownRenderMode
    let preloadedImages: [URL: CGImage]

    var body: some View {
        let renderData = MarkdownAttributedStringBuilder(style: style, context: context)
            .renderData(for: inlines)

        if mode == .pdf {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(MarkdownPDFInlineFragment.coalesced(renderData.pdfFragments)) { fragment in
                    switch fragment.content {
                    case let .text(text):
                        if !text.characters.isEmpty {
                            Text(text)
                        }
                    case let .image(image):
                        let url = MarkdownImageView.resolvedURL(for: image.source, context: context)
                        MarkdownImageView(
                            reference: image,
                            context: context,
                            mode: mode,
                            preloadedImage: url.flatMap { preloadedImages[$0] }
                        )
                    }
                }
            }
        } else if renderData.imageReferences.isEmpty, renderData.attachmentReferences.isEmpty {
            Text(renderData.attributedText)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if !renderData.plainText.isEmpty {
                    Text(renderData.attributedText)
                }

                ForEach(renderData.imageReferences) { image in
                    MarkdownImageView(reference: image, context: context)
                }

                ForEach(renderData.attachmentReferences) { attachment in
                    MarkdownAttachmentView(reference: attachment)
                }
            }
        }
    }
}

struct MarkdownImageReference: Equatable, Identifiable {
    let id: String
    let source: String?
    let title: String?
    let alt: String
}

struct MarkdownAttachmentReference: Equatable, Identifiable {
    let id: String
    let url: URL
    let filename: String
}

struct MarkdownInlineRenderData {
    var attributedText: AttributedString
    var pdfText: AttributedString
    var pdfFragments: [MarkdownPDFInlineFragment]
    var plainText: String
    var imageReferences: [MarkdownImageReference]
    var attachmentReferences: [MarkdownAttachmentReference]
}

struct MarkdownPDFInlineFragment: Identifiable {
    enum Content {
        case text(AttributedString)
        case image(MarkdownImageReference)
    }

    let id: Int
    let content: Content

    static func coalesced(_ fragments: [MarkdownPDFInlineFragment]) -> [MarkdownPDFInlineFragment] {
        var result: [MarkdownPDFInlineFragment] = []

        for fragment in fragments {
            guard case let .text(text) = fragment.content,
                  let lastIndex = result.indices.last,
                  case let .text(previousText) = result[lastIndex].content
            else {
                result.append(fragment)
                continue
            }

            var combinedText = previousText
            combinedText += text
            result[lastIndex] = MarkdownPDFInlineFragment(id: result[lastIndex].id, content: .text(combinedText))
        }

        return result
    }
}

struct MarkdownAttributedStringBuilder {
    let style: MarkdownStyle
    let context: MarkdownRenderContext

    func renderData(for inlines: [MarkdownInline]) -> MarkdownInlineRenderData {
        var result = MarkdownInlineRenderData(
            attributedText: AttributedString(),
            pdfText: AttributedString(),
            pdfFragments: [],
            plainText: "",
            imageReferences: [],
            attachmentReferences: []
        )

        for inline in inlines {
            let inlineResult = renderData(for: inline)
            result.attributedText += inlineResult.attributedText
            result.pdfText += inlineResult.pdfText
            let baseFragmentID = result.pdfFragments.count
            result.pdfFragments.append(contentsOf: inlineResult.pdfFragments.enumerated().map { offset, fragment in
                MarkdownPDFInlineFragment(id: baseFragmentID + offset, content: fragment.content)
            })
            result.plainText += inlineResult.plainText
            result.imageReferences.append(contentsOf: inlineResult.imageReferences)
            result.attachmentReferences.append(contentsOf: inlineResult.attachmentReferences)
        }

        result.plainText = result.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    private func renderData(for inline: MarkdownInline) -> MarkdownInlineRenderData {
        switch inline {
        case let .text(text):
            MarkdownInlineRenderData(
                attributedText: AttributedString(text),
                pdfText: AttributedString(text),
                pdfFragments: [MarkdownPDFInlineFragment(id: 0, content: .text(AttributedString(text)))],
                plainText: text,
                imageReferences: [],
                attachmentReferences: []
            )
        case let .strong(children):
            renderData(for: children, intent: .stronglyEmphasized)
        case let .emphasis(children):
            renderData(for: children, intent: .emphasized)
        case let .strikethrough(children):
            renderData(for: children, intent: .strikethrough)
        case let .code(code):
            MarkdownInlineRenderData(
                attributedText: attributedString(
                    for: code,
                    intent: .code,
                    font: style.inlineCodeFont,
                    foregroundColor: style.codeTextColor
                ),
                pdfText: attributedString(
                    for: code,
                    intent: .code,
                    font: style.inlineCodeFont,
                    foregroundColor: style.codeTextColor
                ),
                pdfFragments: [
                    MarkdownPDFInlineFragment(
                        id: 0,
                        content: .text(
                            attributedString(
                                for: code,
                                intent: .code,
                                font: style.inlineCodeFont,
                                foregroundColor: style.codeTextColor
                            )
                        )
                    )
                ],
                plainText: code,
                imageReferences: [],
                attachmentReferences: []
            )
        case let .link(destination, _, children):
            renderLink(destination: destination, children: children)
        case let .image(source, title, alt):
            MarkdownInlineRenderData(
                attributedText: AttributedString(alt),
                pdfText: AttributedString(),
                pdfFragments: [MarkdownPDFInlineFragment(id: 0, content: .image(
                    MarkdownImageReference(
                        id: "\(source ?? "")|\(title ?? "")|\(alt)",
                        source: source,
                        title: title,
                        alt: alt
                    )
                ))],
                plainText: "",
                imageReferences: [
                    MarkdownImageReference(
                        id: "\(source ?? "")|\(title ?? "")|\(alt)",
                        source: source,
                        title: title,
                        alt: alt
                    )
                ],
                attachmentReferences: []
            )
        case .softBreak:
            MarkdownInlineRenderData(
                attributedText: AttributedString(" "),
                pdfText: AttributedString(" "),
                pdfFragments: [MarkdownPDFInlineFragment(id: 0, content: .text(AttributedString(" ")))],
                plainText: " ",
                imageReferences: [],
                attachmentReferences: []
            )
        case .lineBreak:
            MarkdownInlineRenderData(
                attributedText: AttributedString("\n"),
                pdfText: AttributedString("\n"),
                pdfFragments: [MarkdownPDFInlineFragment(id: 0, content: .text(AttributedString("\n")))],
                plainText: "\n",
                imageReferences: [],
                attachmentReferences: []
            )
        }
    }

    private func renderData(
        for children: [MarkdownInline],
        intent: InlinePresentationIntent
    ) -> MarkdownInlineRenderData {
        var result = renderData(for: children)
        result.attributedText.inlinePresentationIntent = intent
        result.pdfText.inlinePresentationIntent = intent
        result.pdfFragments = result.pdfFragments.map { fragment in
            guard case let .text(text) = fragment.content else {
                return fragment
            }

            var formattedText = text
            formattedText.inlinePresentationIntent = intent
            return MarkdownPDFInlineFragment(id: fragment.id, content: .text(formattedText))
        }
        return result
    }

    private func renderLink(destination: String, children: [MarkdownInline]) -> MarkdownInlineRenderData {
        if let attachmentReference = attachmentReference(for: destination) {
            return MarkdownInlineRenderData(
                attributedText: AttributedString(),
                pdfText: AttributedString(),
                pdfFragments: [],
                plainText: "",
                imageReferences: [],
                attachmentReferences: [attachmentReference]
            )
        }

        var result = renderData(for: children)
        guard let url = resolvedURL(for: destination) else {
            return result
        }

        result.attributedText.link = url
        result.attributedText.foregroundColor = style.linkColor
        result.attributedText.underlineStyle = .single
        result.pdfText.link = url
        result.pdfText.foregroundColor = style.linkColor
        result.pdfText.underlineStyle = .single
        if isImageAssetLink(destination) {
            result.pdfText = AttributedString()
            result.pdfFragments = []
        } else {
            result.pdfFragments = result.pdfFragments.map { fragment in
                guard case let .text(text) = fragment.content else {
                    return fragment
                }

                var linkedText = text
                linkedText.link = url
                linkedText.foregroundColor = style.linkColor
                linkedText.underlineStyle = .single
                return MarkdownPDFInlineFragment(id: fragment.id, content: .text(linkedText))
            }
        }
        return result
    }

    private func attributedString(
        for text: String,
        intent: InlinePresentationIntent,
        font: Font? = nil,
        foregroundColor: Color? = nil
    ) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.inlinePresentationIntent = intent
        if let font {
            attributed.font = font
        }
        if let foregroundColor {
            attributed.foregroundColor = foregroundColor
        }
        return attributed
    }

    private func resolvedURL(for destination: String) -> URL? {
        if let absoluteURL = URL(string: destination), absoluteURL.scheme != nil {
            return absoluteURL
        }

        if destination.hasPrefix("#") {
            return URL(string: destination)
        }

        guard let noteURL = context.noteURL else {
            return URL(string: destination)
        }

        return URL(string: destination, relativeTo: noteURL)?.absoluteURL
    }

    private func attachmentReference(for destination: String) -> MarkdownAttachmentReference? {
        guard let resolvedURL = MarkdownAttachmentReferences.resolve(
            destination,
            assetBaseURL: context.assetBaseURL
        ),
            resolvedURL.isFileURL
        else {
            return nil
        }

        let contentType = try? resolvedURL.resourceValues(forKeys: [.contentTypeKey]).contentType
        let fallbackType = contentType ?? UTType(filenameExtension: resolvedURL.pathExtension)
        guard TextBundleAssetKind(
            contentType: fallbackType,
            filename: resolvedURL.lastPathComponent
        ) == .attachment else {
            return nil
        }

        return MarkdownAttachmentReference(
            id: resolvedURL.standardizedFileURL.path,
            url: resolvedURL,
            filename: resolvedURL.lastPathComponent
        )
    }

    private func isImageAssetLink(_ destination: String) -> Bool {
        guard let resolvedURL = MarkdownAttachmentReferences.resolve(
            destination,
            assetBaseURL: context.assetBaseURL
        ),
            resolvedURL.isFileURL
        else {
            return false
        }

        let contentType = try? resolvedURL.resourceValues(forKeys: [.contentTypeKey]).contentType
        let fallbackType = contentType ?? UTType(filenameExtension: resolvedURL.pathExtension)
        return TextBundleAssetKind(
            contentType: fallbackType,
            filename: resolvedURL.lastPathComponent
        ).isImage
    }
}

private struct MarkdownAttachmentView: View {
    @Environment(\.secondaryBackgroundFill) private var secondaryBackgroundFill
    #if os(iOS)
    @State private var previewedAttachment: AttachmentPreviewItem?
    #endif

    let reference: MarkdownAttachmentReference

    var body: some View {
        Button {
            openAttachment()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc")
                    .foregroundStyle(.secondary)
                Text(displayFilename)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(secondaryBackgroundFill.view)
            .clipShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Attachment")
        .accessibilityValue(reference.filename)
        #if os(iOS)
            .sheet(item: $previewedAttachment) { item in
                AttachmentPreviewController(item: item)
            }
        #endif
    }

    private var displayFilename: String {
        let fileURL = URL(fileURLWithPath: reference.filename)
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = fileURL.pathExtension
        guard !fileExtension.isEmpty, baseName.count > 36 else {
            return reference.filename
        }

        let prefix = baseName.prefix(33)
        return "\(prefix)...\(fileExtension)"
    }

    private func openAttachment() {
        #if os(macOS)
        NSWorkspace.shared.open(reference.url)
        #else
        previewedAttachment = AttachmentPreviewItem(url: reference.url)
        #endif
    }
}
