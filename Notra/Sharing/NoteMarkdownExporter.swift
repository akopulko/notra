import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct NoteMarkdownShareItem: Equatable, Sendable, Transferable {
    let fileURL: URL
    let suggestedFilename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .notraMarkdown) { item in
            SentTransferredFile(item.fileURL)
        }
    }
}

struct NoteMarkdownExporter {
    func export(payload: NoteExportPayload) throws -> NoteMarkdownShareItem {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let filename = NoteExportFilename.sanitizedFilename(
            payload.suggestedFilename,
            fileExtension: "markdown"
        )
        let fileURL = directoryURL.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try payload.markdown.write(to: fileURL, atomically: true, encoding: .utf8)
            return NoteMarkdownShareItem(fileURL: fileURL, suggestedFilename: filename)
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            throw error
        }
    }
}
