import Foundation

struct NoteSummary: Identifiable, Equatable {
    static let emptyPreviewText = "<Empty Note>"

    let id: URL
    let url: URL
    let previewText: String
    let previewFirstLineIsHeading: Bool
    let createdAt: Date
    let modifiedAt: Date

    init(
        url: URL,
        previewText: String,
        previewFirstLineIsHeading: Bool = false,
        createdAt: Date,
        modifiedAt: Date
    ) {
        id = url
        self.url = url
        self.previewText = previewText
        self.previewFirstLineIsHeading = previewFirstLineIsHeading
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
        id = url
        self.url = url
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
