import Foundation

struct MarkdownRenderInput: Equatable {
    let markdown: String
    let context: MarkdownRenderContext
    let mode: MarkdownRenderMode

    init(
        markdown: String,
        context: MarkdownRenderContext,
        mode: MarkdownRenderMode = .preview
    ) {
        self.markdown = markdown
        self.context = context
        self.mode = mode
    }
}

struct MarkdownRenderContext: Equatable, Sendable {
    let noteURL: URL?
    let assetBaseURL: URL?

    static func textBundle(noteURL: URL?) -> MarkdownRenderContext {
        MarkdownRenderContext(
            noteURL: noteURL,
            assetBaseURL: noteURL?.appendingPathComponent(TextBundleNoteRepository.assetsFolder, isDirectory: true)
        )
    }

    static let empty = MarkdownRenderContext(noteURL: nil, assetBaseURL: nil)
}
