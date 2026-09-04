import ImageIO
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Renders one sidebar note row, including preview text, dates, tags, and attachment state.
struct NoteRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let note: NoteSummary
    let sortField: NoteSortField
    let showsNotePreview: Bool

    private let previewLineLimit = 3

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                previewText
                HStack(spacing: 4) {
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .imageScale(.small)
                            .foregroundStyle(italicColor)
                            .accessibilityHidden(true)
                    }
                    formattedDate
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if note.attachmentSummary.showsPaperclip {
                        Image(systemName: "paperclip")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                if !note.tags.isEmpty {
                    NoteRowTagsLine(tags: note.tags, colors: tagColors)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let thumbnailURL = note.attachmentSummary.firstLinkedImageURL {
                NoteRowThumbnail(url: thumbnailURL)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var previewText: some View {
        if note.previewFirstLineIsHeading {
            let lines = note.previewText.components(separatedBy: .newlines)
            let remainingPreviewText = lines.dropFirst().joined(separator: "\n")
            VStack(alignment: .leading, spacing: 2) {
                titleText(lines.first ?? NoteSummary.emptyPreviewText)
                if showsNotePreview, !remainingPreviewText.isEmpty {
                    Text(verbatim: remainingPreviewText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(max(previewLineLimit - 1, 1))
                        .truncationMode(.tail)
                }
            }
        } else {
            Text(verbatim: note.previewText)
                .font(.body)
                .lineLimit(showsNotePreview ? previewLineLimit : 1)
                .truncationMode(.tail)
        }
    }

    private var formattedDate: some View {
        Text(
            sortField == .dateCreated ? note.createdAt : note.modifiedAt,
            format: .dateTime.month().day().year().hour().minute()
        )
    }

    private func titleText(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.title3)
            .fontWeight(.bold)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var tagColors: MarkdownTagColors {
        MarkdownTheme.preferred(for: colorScheme).previewHashtagColors
    }

    /// Reuses the Markdown preview's italic role for the pinned-note indicator.
    private var italicColor: Color {
        MarkdownTheme.preferred(for: colorScheme).preview.italic.color
    }

    private var accessibilityValue: String {
        [note.isPinned ? "Pinned" : nil, note.attachmentSummary.accessibilityDescription]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

/// Keeps sidebar tags visually separate while fitting them into a single row.
private struct NoteRowTagsLine: View {
    let tags: [NoteTag]
    let colors: MarkdownTagColors

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tagsStack(tags: tags, showsOverflow: false)
            ForEach(truncatedTagCounts, id: \.self) { visibleCount in
                tagsStack(
                    tags: Array(tags.prefix(visibleCount)),
                    showsOverflow: true
                )
            }
            tagsStack(tags: [], showsOverflow: true)
        }
        .font(.caption2)
        .lineLimit(1)
    }

    private var truncatedTagCounts: [Int] {
        guard tags.count > 1 else {
            return []
        }

        return Array(stride(from: tags.count - 1, through: 1, by: -1))
    }

    private func tagsStack(tags visibleTags: [NoteTag], showsOverflow: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(visibleTags) { tag in
                tagText(tag.prefixedDisplayName)
            }

            if showsOverflow {
                tagText("...")
            }
        }
    }

    private func tagText(_ text: String) -> some View {
        Text(verbatim: text)
            .foregroundStyle(colors.foregroundColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(colors.backgroundColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Loads the first linked image for a note row without blocking list rendering.
private struct NoteRowThumbnail: View {
    let url: URL

    @State private var image: CGImage?

    private let size: CGFloat = 44

    var body: some View {
        ZStack {
            if let image {
                platformImage(for: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.tertiary)
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 6, style: .continuous))
        .contentShape(.rect)
        .task(id: url) {
            image = nil
            image = await NoteRowThumbnailLoader.shared.thumbnail(for: url)
        }
    }

    private func platformImage(for image: CGImage) -> Image {
        #if os(iOS)
        Image(uiImage: UIImage(cgImage: image))
        #else
        Image(nsImage: NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        ))
        #endif
    }
}

/// Serializes and caches small note-row thumbnail reads.
private actor NoteRowThumbnailLoader {
    static let shared = NoteRowThumbnailLoader()

    private var cache: [URL: CGImage] = [:]

    func thumbnail(for url: URL) async -> CGImage? {
        if let cachedImage = cache[url] {
            return cachedImage
        }

        let image = await Task.detached(priority: .utility) {
            Self.makeThumbnail(for: url)
        }.value

        if let image {
            cache[url] = image
        }
        return image
    }

    private static func makeThumbnail(for url: URL) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 96
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }
}
