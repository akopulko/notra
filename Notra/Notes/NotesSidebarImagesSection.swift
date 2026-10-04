import SwiftUI

/// Shows library-wide linked image shortcuts in a compact grid.
struct NotesSidebarImagesSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsAllImages = false

    let images: [NoteSidebarImage]
    let totalImageCount: Int
    let revealNote: (URL) -> Void

    private var visibleImages: ArraySlice<NoteSidebarImage> {
        images.prefix(showsAllImages ? 100 : 10)
    }

    var body: some View {
        Section {
            if images.isEmpty {
                Text(.noImages)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 56, maximum: 72), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(visibleImages) { item in
                        NoteSidebarImageTile(item: item) {
                            revealNote(item.noteID)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            HStack {
                Text("Images (\(visibleImages.count)/\(totalImageCount))")
                    .foregroundStyle(MarkdownTheme.preferred(for: colorScheme).preview.headingSecondary.color)
                Spacer()
                if images.count > 10 {
                    Button {
                        showsAllImages.toggle()
                    } label: {
                        Text(showsAllImages ? .showLess : .showAll)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("notes.sidebar.imageVisibilityToggle")
                }
            }
        }
    }
}

private struct NoteSidebarImageTile: View {
    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: Image?

    let item: NoteSidebarImage
    let action: () -> Void

    private var maximumPixelSize: Int {
        Int(ceil(72 * displayScale))
    }

    var body: some View {
        Button(action: action) {
            GeometryReader { geometry in
                ZStack {
                    Rectangle()
                        .fill(.quaternary)
                    if let thumbnail {
                        thumbnail
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } else {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(.rect(cornerRadius: 6))
                .accessibilityHidden(true)
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text(String(
                localized: "sidebarImageOpenNote",
                defaultValue: "Open note \(item.notePreview)",
                comment: "Sidebar image shortcut: open the note containing this image."
            ))
        )
        .accessibilityValue(item.imageURL.lastPathComponent)
        .accessibilityIdentifier("notes.sidebar.image.\(item.imageURL.absoluteString)")
        .task(id: maximumPixelSize) {
            thumbnail = nil
            guard let cgImage = await ThumbnailService.shared.thumbnail(
                for: item.imageURL,
                maximumPixelSize: maximumPixelSize
            ), !Task.isCancelled else {
                return
            }
            thumbnail = Image(decorative: cgImage, scale: displayScale, orientation: .up)
        }
        .accessibilityElement(children: .ignore)
    }
}
