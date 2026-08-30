import Foundation
import UniformTypeIdentifiers

/// Immutable snapshot passed from the store to Markdown and PDF exporters.
struct NoteExportPayload: Equatable, Sendable {
    let markdown: String
    let noteURL: URL
    let suggestedFilename: String
}

/// Produces safe, user-facing filenames while preserving the source note's title.
enum NoteExportFilename {
    static func sanitizedFilename(_ filename: String, fileExtension: String) -> String {
        let baseName = URL(fileURLWithPath: filename)
            .deletingPathExtension()
            .lastPathComponent
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let sanitized = String(
            baseName.unicodeScalars.map { allowedCharacters.contains($0) ? Character($0) : "-" }
        )
        .trimmingCharacters(in: CharacterSet(charactersIn: " -_"))

        return (sanitized.isEmpty ? "Note" : sanitized) + ".\(fileExtension)"
    }
}

extension UTType {
    nonisolated static let notraMarkdown = UTType(filenameExtension: "markdown")
        ?? UTType(importedAs: TextBundleInfo.markdownType)
}
