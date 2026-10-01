#if os(macOS)
import Foundation
import UniformTypeIdentifiers

enum NoteMarkdownImporter {
    nonisolated static let supportedFilenameExtensions = ["md", "markdown", "mdown", "mkd", "mkdn"]

    nonisolated static let allowedContentTypes: [UTType] = {
        var contentTypes = [UTType.notraMarkdown]
        for filenameExtension in supportedFilenameExtensions {
            guard let contentType = UTType(filenameExtension: filenameExtension, conformingTo: .plainText),
                  !contentTypes.contains(contentType)
            else {
                continue
            }
            contentTypes.append(contentType)
        }
        return contentTypes
    }()

    nonisolated static func readMarkdown(from url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return try String(contentsOf: url, encoding: .utf8)
        }.value
    }
}
#endif
