import SwiftUI

/// Renders one attachment with its type-specific icon, preview action, and deletion affordance.
struct AttachmentRow: View {
    let attachment: TextBundleAsset

    private var formattedByteCount: String {
        ByteCountFormatter.string(
            fromByteCount: attachment.byteCount,
            countStyle: .file
        )
    }

    private var linkState: String {
        attachment.isLinked ? "Linked" : "Not Linked"
    }

    var body: some View {
        HStack(spacing: 12) {
            if attachment.kind == .image {
                AttachmentThumbnailView(url: attachment.url)
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 6))
            } else {
                AttachmentFileIconView()
                    .frame(width: 40, height: 40)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.filename)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(
                        linkState,
                        systemImage: attachment.isLinked ? "link" : "link.slash"
                    )
                    Text(formattedByteCount)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(linkState), \(formattedByteCount)")
    }
}

/// Chooses a familiar file icon for attachments that are not rendered as image thumbnails.
private struct AttachmentFileIconView: View {
    var body: some View {
        Image(systemName: "doc")
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary)
            .clipShape(.rect(cornerRadius: 6))
            .accessibilityHidden(true)
    }
}

/// Loads and displays an attachment thumbnail without making the inspector wait on disk I/O.
private struct AttachmentThumbnailView: View {
    @State private var image: Image?

    let url: URL

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .clipped()
        .task(id: url) {
            image = await loadImage()
        }
        .accessibilityHidden(true)
    }

    private func loadImage() async -> Image? {
        let cgImage = await ThumbnailService.shared.thumbnail(for: url, maximumPixelSize: 192)

        guard !Task.isCancelled, let cgImage else {
            return nil
        }
        return Image(decorative: cgImage, scale: 1, orientation: .up)
    }
}
