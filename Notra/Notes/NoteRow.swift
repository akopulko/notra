import ImageIO
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Renders one sidebar note row, including preview text, dates, tags, and attachment state.
struct NoteRow: View {
    let note: NoteSummary
    let sortField: NoteSortField

    private let previewLineLimit = 3

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                previewText
                HStack(spacing: 4) {
                    Text(
                        sortField == .dateCreated ? note.createdAt : note.modifiedAt,
                        format: .dateTime.month().day().year().hour().minute()
                    )
                    if note.attachmentSummary.showsPaperclip {
                        Image(systemName: "paperclip")
                            .imageScale(.small)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let thumbnailURL = note.attachmentSummary.firstLinkedImageURL {
                NoteRowThumbnail(url: thumbnailURL)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(note.attachmentSummary.accessibilityDescription)
    }

    @ViewBuilder
    private var previewText: some View {
        if note.previewFirstLineIsHeading {
            let lines = note.previewText.components(separatedBy: .newlines)
            let remainingPreviewText = lines.dropFirst().joined(separator: "\n")
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: lines.first ?? NoteSummary.emptyPreviewText)
                    .font(.title3)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !remainingPreviewText.isEmpty {
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
                .lineLimit(previewLineLimit)
                .truncationMode(.tail)
        }
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
