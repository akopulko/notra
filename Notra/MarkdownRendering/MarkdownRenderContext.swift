import Foundation

/// Captures the source and rendering options that define one preview parse.
struct MarkdownRenderInput: Equatable {
    /// Markdown source used to produce the document.
    let markdown: String
    /// Asset and note URLs used while resolving local destinations.
    let context: MarkdownRenderContext
    /// Rendering mode controls lazy preview versus eager PDF layout.
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

/// Carries platform-neutral values needed while rendering one Markdown document.
struct MarkdownRenderContext: Equatable, Sendable {
    /// Source TextBundle URL, when the document belongs to a saved note.
    let noteURL: URL?
    /// Assets directory used to resolve bundle-relative image and attachment paths.
    let assetBaseURL: URL?

    /// Creates a context whose asset root follows the supplied TextBundle URL.
    static func textBundle(noteURL: URL?) -> MarkdownRenderContext {
        MarkdownRenderContext(
            noteURL: noteURL,
            assetBaseURL: noteURL?.appendingPathComponent(TextBundleNoteRepository.assetsFolder, isDirectory: true)
        )
    }

    static let empty = MarkdownRenderContext(noteURL: nil, assetBaseURL: nil)
}
