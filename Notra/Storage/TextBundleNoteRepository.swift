import Foundation

/// Storage failures that can be translated into user-facing note-operation errors.
enum NoteRepositoryError: Equatable, LocalizedError {
    case invalidBundle(URL)
    case noteNotFound
    case storageUnavailable
    case invalidMetadata
    case invalidImageData
    case imageEncodingFailed
    case invalidAttachment
    case attachmentTooLarge(filename: String, byteCount: Int64, limit: Int64)

    var errorDescription: String? {
        switch self {
        case .invalidBundle:
            "The note bundle is invalid."
        case .noteNotFound:
            "The selected note could not be found."
        case .storageUnavailable:
            "The note storage location is unavailable."
        case .invalidMetadata:
            "The note metadata could not be updated."
        case .invalidImageData:
            "The selected file is not a supported image."
        case .imageEncodingFailed:
            "The image could not be saved."
        case .invalidAttachment:
            "The selected attachment is invalid."
        case let .attachmentTooLarge(filename, byteCount, limit):
            """
            "\(filename)" is \(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)). \
            The maximum attachment size is \(ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)).
            """
        }
    }
}

/// Reads and writes notes as specification-compatible TextBundles on local or iCloud storage.
struct TextBundleNoteRepository: Sendable {
    /// TextBundle layout constants shared by storage, import, preview, and export code.
    nonisolated static let bundleExtension = "textbundle"
    nonisolated static let textFilename = "text.markdown"
    nonisolated static let infoFilename = "info.json"
    nonisolated static let assetsFolder = "assets"
    nonisolated static let appMetadataKey = "app.notra.Notra"

    /// Root directory containing note bundles for the selected storage location.
    nonisolated let rootURL: URL
    /// The location represented by `rootURL`, retained for settings and inspector descriptions.
    nonisolated let storageLocation: NoteStorageLocation

    init(rootURL: URL, isUsingICloud: Bool = false) {
        self.rootURL = rootURL
        storageLocation = isUsingICloud ? .iCloud : .localStore
    }

    var isUsingICloud: Bool {
        storageLocation == .iCloud
    }

    /// Creates the repository root before any directory enumeration or bundle creation.
    nonisolated func prepareStorage() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    /// Human-readable storage label used by logging and settings.
    var storageDescription: String {
        if isUsingICloud {
            return "iCloud Drive / Notra"
        }

        #if os(iOS)
        return "On My iPhone / Notra"
        #else
        return "On My Mac / Notra"
        #endif
    }

    /// Short location label shown in the selected-note inspector.
    var noteLocationDescription: String {
        if isUsingICloud {
            return "iCloud/Notra"
        }

        #if os(iOS)
        return "On My Phone/Notra"
        #else
        return "On My Mac/Notra"
        #endif
    }

    /// Enumerates valid TextBundles and derives lightweight previews without loading editor bodies.
    nonisolated func listNotes() throws -> [NoteSummary] {
        try prepareStorage()
        try Task.checkCancellation()

        let urls = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let noteURLs = urls.filter { $0.pathExtension == Self.bundleExtension }
        return try noteURLs.map { url in
            try Task.checkCancellation()
            return try summary(for: url)
        }
    }

    /// Derives the sidebar projection for one bundle without enumerating the whole notes library.
    nonisolated func summary(
        for url: URL,
        analysis: MarkdownDocumentAnalysis? = nil
    ) throws -> NoteSummary {
        let createdAt = try url.resourceValues(forKeys: [.creationDateKey])
            .creationDate ?? .distantPast
        let markdown = try markdownContent(in: url)
        let analysis = analysis ?? MarkdownDocumentAnalysis.analyse(markdown: markdown)
        let preview = Self.preview(for: markdown)
        let metadata = summaryMetadata(at: url)
        let attachmentSummary = try attachmentSummary(for: url, analysis: analysis)
        let modifiedAt = try modifiedDate(of: url)
        return NoteSummary(
            url: url,
            previewText: preview.text,
            previewFirstLineIsHeading: preview.firstLineIsHeading,
            tags: metadata.tags,
            hasChecklist: analysis.hasChecklist,
            attachmentSummary: attachmentSummary,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            pinnedAt: metadata.pinnedAt
        )
    }

    /// Loads Markdown and Notra metadata from one TextBundle into an editable note value.
    func loadNote(at url: URL) throws -> Note {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw NoteRepositoryError.noteNotFound
        }

        let textURL = url.appendingPathComponent(Self.textFilename)
        let markdown = try String(contentsOf: textURL, encoding: .utf8)
        let metadata = try noteMetadata(at: url)
        let createdAt = try url.resourceValues(forKeys: [.creationDateKey])
            .creationDate ?? .distantPast
        return try Note(
            url: url,
            markdown: markdown,
            metadata: metadata,
            createdAt: createdAt,
            modifiedAt: modifiedDate(of: url)
        )
    }

    /// Creates a unique TextBundle with spec metadata, initial Markdown, and an assets directory.
    func createNote(initialMarkdown: String = "") throws -> Note {
        try prepareStorage()

        let bundleURL = try uniqueBundleURL()

        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: bundleURL.appendingPathComponent(Self.assetsFolder, isDirectory: true),
            withIntermediateDirectories: true
        )

        let infoData = try JSONEncoder.notra.encode(TextBundleInfo())
        try infoData.write(to: bundleURL.appendingPathComponent(Self.infoFilename), options: .atomic)

        try initialMarkdown.write(
            to: bundleURL.appendingPathComponent(Self.textFilename),
            atomically: true,
            encoding: .utf8
        )
        return try loadNote(at: bundleURL)
    }

    /// Writes only the Markdown body for an existing note, leaving metadata untouched.
    func save(_ note: Note) throws {
        guard FileManager.default.fileExists(atPath: note.url.path(percentEncoded: false)) else {
            throw NoteRepositoryError.noteNotFound
        }

        try note.markdown.write(
            to: note.url.appendingPathComponent(Self.textFilename),
            atomically: true,
            encoding: .utf8
        )
    }

    /// Removes one whole TextBundle after verifying that it still exists.
    func delete(_ summary: NoteSummary) throws {
        guard FileManager.default.fileExists(atPath: summary.url.path(percentEncoded: false)) else {
            throw NoteRepositoryError.noteNotFound
        }
        try FileManager.default.removeItem(at: summary.url)
    }
}

private extension TextBundleNoteRepository {
    /// Generates a collision-free UUID bundle name, bounded to avoid an infinite filesystem loop.
    private func uniqueBundleURL() throws -> URL {
        for _ in 0..<10 {
            let bundleURL = rootURL
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathExtension(Self.bundleExtension)
            if !FileManager.default.fileExists(atPath: bundleURL.path(percentEncoded: false)) {
                return bundleURL
            }
        }

        throw NoteRepositoryError.storageUnavailable
    }
}

private extension JSONEncoder {
    static var notra: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
