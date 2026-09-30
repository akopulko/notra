import Foundation
@testable import Notra
import Testing

/// Verifies raw Markdown export and safe filename generation without mutating the source note.
struct NoteMarkdownExporterTests {
    @Test
    func `exports raw markdown to a markdown file`() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotraMarkdownExporterTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let markdown = "# Heading\n\n![Photo](assets/photo.jpg)\n\n```mermaid\nflowchart TD\nA --> B\n```"
        let item = try NoteMarkdownExporter().export(
            payload: NoteExportPayload(
                markdown: markdown,
                noteURL: directoryURL.appendingPathComponent("Test Note.textbundle"),
                suggestedFilename: "Test Note.textbundle"
            )
        )
        defer { try? FileManager.default.removeItem(at: item.fileURL.deletingLastPathComponent()) }

        #expect(item.suggestedFilename == "Test Note.markdown")
        #expect(try String(contentsOf: item.fileURL, encoding: .utf8) == markdown)
    }

    @Test
    func `sanitizes markdown export filenames`() {
        #expect(
            NoteExportFilename.sanitizedFilename(
                "Project: Notes?.textbundle",
                fileExtension: "markdown"
            ) == "Project- Notes.markdown"
        )
        #expect(NoteExportFilename.sanitizedFilename("   ", fileExtension: "markdown") == "Note.markdown")
    }
}
