import Foundation

/// One linked local image and the note that owns its TextBundle asset.
struct NoteSidebarImage: Identifiable, Equatable, Sendable {
    let noteID: URL
    let imageURL: URL
    let notePreview: String

    nonisolated var id: URL {
        imageURL
    }

    /// Projects images from already-sorted notes without flattening past the display limit.
    nonisolated static func images(in notes: [NoteSummary]) -> [NoteSidebarImage] {
        let maximumCount = 100
        var images: [NoteSidebarImage] = []
        images.reserveCapacity(min(maximumCount, notes.count))

        for note in notes {
            for imageURL in note.attachmentSummary.linkedImageURLs {
                images.append(NoteSidebarImage(
                    noteID: note.id,
                    imageURL: imageURL,
                    notePreview: note.previewText
                ))
                if images.count == maximumCount {
                    return images
                }
            }
        }

        return images
    }
}
