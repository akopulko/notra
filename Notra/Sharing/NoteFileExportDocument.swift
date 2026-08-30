import SwiftUI
import UniformTypeIdentifiers

/// Adapts exported Markdown or PDF bytes to SwiftUI's file-exporter API.
struct NoteFileExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.pdf, .notraMarkdown]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Holds a generated export until the platform save flow is ready to present it.
struct PendingNoteFileExport: Identifiable {
    let id = UUID()
    let document: NoteFileExportDocument
    let contentType: UTType
    let suggestedFilename: String
}
