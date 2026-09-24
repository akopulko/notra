import Foundation

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
