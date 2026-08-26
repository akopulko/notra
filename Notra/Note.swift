import Foundation

#if canImport(Darwin)
import Darwin
#endif

struct NoteAttachmentSummary: Equatable, Sendable {
    static let empty = NoteAttachmentSummary(
        firstLinkedImageURL: nil,
        hasLinkedNonImageAttachment: false
    )

    let firstLinkedImageURL: URL?
    let hasLinkedNonImageAttachment: Bool

    var showsPaperclip: Bool {
        firstLinkedImageURL != nil || hasLinkedNonImageAttachment
    }

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

struct NoteSummary: Identifiable, Equatable {
    static let emptyPreviewText = "<Empty Note>"

    let id: URL
    let url: URL
    let previewText: String
    let previewFirstLineIsHeading: Bool
    let attachmentSummary: NoteAttachmentSummary
    let createdAt: Date
    let modifiedAt: Date

    init(
        url: URL,
        previewText: String,
        previewFirstLineIsHeading: Bool = false,
        attachmentSummary: NoteAttachmentSummary = .empty,
        createdAt: Date,
        modifiedAt: Date
    ) {
        let normalizedURL = url.notraCanonicalFileURL
        id = normalizedURL
        self.url = normalizedURL
        self.previewText = previewText
        self.previewFirstLineIsHeading = previewFirstLineIsHeading
        self.attachmentSummary = attachmentSummary
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

struct Note: Identifiable, Equatable {
    let id: URL
    let url: URL
    var markdown: String
    var metadata: NoteMetadata
    var createdAt: Date
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

enum NoteFormattingCommand: CaseIterable, Hashable {
    case bold
    case italic
    case heading
    case unorderedList
    case orderedList
    case quote
    case todo
    case code
    case link
    case table
    case image
}

enum MarkdownHeadingLevel: Int, CaseIterable, Hashable {
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
