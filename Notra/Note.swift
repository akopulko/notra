import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Summarizes attachment visibility without loading all attachment metadata into a row.
struct NoteAttachmentSummary: Equatable, Sendable {
    /// Empty summary used when the note has no links to assets.
    static let empty = NoteAttachmentSummary(
        firstLinkedImageURL: nil,
        hasLinkedNonImageAttachment: false
    )

    /// First linked image, if one exists, used for the compact note-row thumbnail.
    let firstLinkedImageURL: URL?
    /// True when at least one linked asset is not an image and needs a paperclip indicator.
    let hasLinkedNonImageAttachment: Bool

    /// Whether the note row should show any attachment affordance.
    var showsPaperclip: Bool {
        firstLinkedImageURL != nil || hasLinkedNonImageAttachment
    }

    /// Accessibility text that distinguishes image content from other attachments.
    var accessibilityDescription: String {
        if firstLinkedImageURL != nil {
            return "Contains image"
        }
        if hasLinkedNonImageAttachment {
            return "Contains attachment"
        }
        return ""
    }
}

/// The lightweight note value used by lists, selection, sorting, and search results.
struct NoteSummary: Identifiable, Equatable {
    /// Shared placeholder used when a note contains no non-empty preview lines.
    static let emptyPreviewText = "<Empty Note>"

    /// Canonical file URL used as the stable SwiftUI and search identity.
    let id: URL
    /// Location of the TextBundle on disk.
    let url: URL
    /// Plain-text preview shown in the sidebar.
    let previewText: String
    /// Preserves heading styling for the first preview line.
    let previewFirstLineIsHeading: Bool
    /// Tags displayed as one compact metadata line in note rows.
    let tags: [NoteTag]
    /// Linked-asset summary used by row icons and thumbnails.
    let attachmentSummary: NoteAttachmentSummary
    /// Bundle creation timestamp used by the date sort.
    let createdAt: Date
    /// Markdown modification timestamp used by the default sort.
    let modifiedAt: Date
    /// Timestamp that keeps pinned notes in a stable, note-owned order.
    let pinnedAt: Date?

    /// Whether the note should remain above the regular sorted notes.
    var isPinned: Bool {
        pinnedAt != nil
    }

    init(
        url: URL,
        previewText: String,
        previewFirstLineIsHeading: Bool = false,
        tags: [NoteTag] = [],
        attachmentSummary: NoteAttachmentSummary = .empty,
        createdAt: Date,
        modifiedAt: Date,
        pinnedAt: Date? = nil
    ) {
        let normalizedURL = url.notraCanonicalFileURL
        id = normalizedURL
        self.url = normalizedURL
        self.previewText = previewText
        self.previewFirstLineIsHeading = previewFirstLineIsHeading
        self.tags = tags
        self.attachmentSummary = attachmentSummary
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.pinnedAt = pinnedAt
    }
}

/// The editable note loaded from a TextBundle, including Markdown and metadata.
struct Note: Identifiable, Equatable {
    /// Canonical file URL used as the stable note identity.
    let id: URL
    /// Location of the persisted TextBundle.
    let url: URL
    /// Editable Markdown body, including links to local assets.
    var markdown: String
    /// Normalized Notra metadata such as tags.
    var metadata: NoteMetadata
    /// Original bundle creation timestamp.
    var createdAt: Date
    /// Last Markdown modification timestamp observed on disk.
    var modifiedAt: Date

    init(
        url: URL,
        markdown: String,
        metadata: NoteMetadata = NoteMetadata(),
        createdAt: Date,
        modifiedAt: Date
    ) {
        let normalizedURL = url.notraCanonicalFileURL
        id = normalizedURL
        self.url = normalizedURL
        self.markdown = markdown
        self.metadata = metadata
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/// The formatting operations exposed by the editor toolbar and menu commands.
enum NoteFormattingCommand: CaseIterable, Hashable {
    case bold
    case italic
    case heading
    case hashtag
    case unorderedList
    case orderedList
    case quote
    case todo
    case code
    case link
    case table
    case image
}

/// The Markdown heading levels supported by the formatting menu.
enum MarkdownHeadingLevel: Int, CaseIterable, Hashable {
    /// The number of `#` markers emitted before heading text.
    case h1 = 1
    case h2
    case h3
    case h4
    case h5
    case h6

    var markdownPrefix: String {
        "\(String(repeating: "#", count: rawValue)) "
    }
}

extension URL {
    var notraCanonicalFileURL: URL {
        guard isFileURL else {
            return standardizedFileURL
        }

        #if canImport(Darwin)
        let filePath = path(percentEncoded: false)
        if let resolvedPath = filePath.withCString({ realpath($0, nil) }) {
            defer { free(resolvedPath) }
            return URL(fileURLWithPath: String(cString: resolvedPath)).standardizedFileURL
        }
        #endif

        return standardizedFileURL
    }
}
