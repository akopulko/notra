import Foundation
import Markdown

/// Serialises deferred Markdown writes away from the main actor.
actor NoteAutosaveWorker {
    /// Validates and atomically persists one editor snapshot without touching observable UI state.
    func save(markdown: String, at noteURL: URL) throws {
        guard FileManager.default.fileExists(atPath: noteURL.path(percentEncoded: false)) else {
            throw CocoaError(.fileNoSuchFile)
        }

        _ = Document(parsing: markdown)
        try markdown.write(
            to: noteURL.appendingPathComponent(TextBundleNoteRepository.textFilename),
            atomically: true,
            encoding: .utf8
        )
    }

    /// Queues behind any active write so destructive repository operations cannot race it.
    func finishPendingWrites() {}
}
