import Foundation
import Markdown

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
            return String(localized: "The note bundle is invalid.")
        case .noteNotFound:
            return String(localized: "The selected note could not be found.")
        case .storageUnavailable:
            return String(localized: "The note storage location is unavailable.")
        case .invalidMetadata:
            return String(localized: "The note metadata could not be updated.")
        case .invalidImageData:
            return String(localized: "The selected file is not a supported image.")
        case .imageEncodingFailed:
            return String(localized: "The image could not be saved.")
        case .invalidAttachment:
            return String(localized: "The selected attachment is invalid.")
        case let .attachmentTooLarge(filename, byteCount, limit):
            let byteCount = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
            let maximumByteCount = ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)
            return String(localized: "\(filename) is \(byteCount). The maximum attachment size is \(maximumByteCount).")
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

    nonisolated init(rootURL: URL, isUsingICloud: Bool = false) {
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
    nonisolated func loadNote(at url: URL) throws -> Note {
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

    /// Publishes an independent, validated copy of every member of a TextBundle.
    func duplicateNote(at sourceURL: URL, preservingPin: Bool) throws -> Note {
        try prepareStorage()
        let source = try loadNote(at: sourceURL)
        let destination = try uniqueBundleURL()
        let stagingParent = rootURL.appendingPathComponent(".duplicate-\(UUID().uuidString)", isDirectory: true)
        var stagedBundle = stagingParent.appendingPathComponent(destination.lastPathComponent, isDirectory: true)
        let fileManager = FileManager.default
        let sourceTextURL = sourceURL.appendingPathComponent(Self.textFilename)
        let dateKeys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey]
        let bundleDates = try sourceURL.resourceValues(forKeys: dateKeys)
        let textDates = try sourceTextURL.resourceValues(forKeys: dateKeys)
        // Ownership begins only after creation succeeds; never clean up a pre-existing directory.
        try fileManager.createDirectory(at: stagingParent, withIntermediateDirectories: false)
        var published = false
        do {
            try fileManager.copyItem(at: sourceURL, to: stagedBundle)
            var textURL = stagedBundle.appendingPathComponent(Self.textFilename)
            try duplicatedMarkdown(from: source.markdown).write(to: textURL, atomically: true, encoding: .utf8)
            if !preservingPin, source.metadata.pinnedAt != nil {
                var metadata = source.metadata
                metadata.pinnedAt = nil
                try updateNoteMetadata(metadata, for: stagedBundle)
            }
            try textURL.setResourceValues(textDates)
            try stagedBundle.setResourceValues(bundleDates)
            _ = try loadNote(at: stagedBundle)
            try fileManager.moveItem(at: stagedBundle, to: destination)
            published = true
            let copy = try loadNote(at: destination)
            try fileManager.removeItem(at: stagingParent)
            return copy
        } catch {
            if published {
                do {
                    try fileManager.removeItem(at: destination)
                } catch {
                    AppLog.error("Failed to roll back duplicated note: \(error.localizedDescription)")
                }
            }
            do {
                try fileManager.removeItem(at: stagingParent)
            } catch {
                AppLog.error("Failed to remove note duplication staging directory: \(error.localizedDescription)")
            }
            throw error
        }
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
    /// Changes only an opening heading's title, preserving the original Markdown slices.
    private func duplicatedMarkdown(from markdown: String) -> String {
        var lines: [Range<String.Index>] = []
        var start = markdown.startIndex
        for index in markdown.indices where markdown[index].isMarkdownLineEnding {
            lines.append(start..<index)
            start = markdown.index(after: index)
        }
        lines.append(start..<markdown.endIndex)

        let heading = Document(parsing: markdown).children.first { _ in true } as? Heading
        if let heading, let sourceRange = heading.range {
            let firstLineIndex = sourceRange.lowerBound.line - 1
            // Source ranges are half-open; Setext headings can end at column one of the following line.
            let lastLineIndex = sourceRange.upperBound.line - (sourceRange.upperBound.column == 1 ? 2 : 1)
            if lines.indices.contains(firstLineIndex), lines.indices.contains(lastLineIndex), lastLineIndex >= firstLineIndex {
                let firstLine = lines[firstLineIndex]
                if let copy = duplicatedATXHeading(in: markdown, lineRange: firstLine, level: heading.level) {
                    return copy
                }
                // cmark may include the following body line in a Setext heading's source range.
                let titleLineIndex = (firstLineIndex..<lastLineIndex).first { index in
                    markdown[lines[index + 1]].range(of: #"^ {0,3}(=+|-+)[ \t]*$"#, options: .regularExpression) != nil
                }
                if let titleLineIndex {
                    let titleLine = lines[titleLineIndex]
                    return replacingDuplicatedTitle(in: markdown, range: trimmedHeadingTitle(in: markdown, range: titleLine))
                }
            }
        }

        let preview = Self.preview(for: markdown).text
        let title = preview == NoteSummary.emptyPreviewText
            ? ""
            : String(preview.split(whereSeparator: \.isNewline).first ?? "")
        let escapedTitle = title.reduce(into: "") { result, character in
            if "\\`*_[]<>#!".contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
        let lineEnding = markdown.first(where: \.isMarkdownLineEnding).map(String.init) ?? "\n"
        return "# " + duplicatedTitle(escapedTitle) + lineEnding + lineEnding + markdown
    }

    private func duplicatedATXHeading(in markdown: String, lineRange: Range<String.Index>, level: Int) -> String? {
        let line = markdown[lineRange]
        let indentation = line.prefix { $0.isHorizontalHeadingWhitespace }
        let markers = line.dropFirst(indentation.count).prefix { $0 == "#" }
        guard !markers.isEmpty, markers.count == level else {
            return nil
        }
        let markerEnd = markdown.index(lineRange.lowerBound, offsetBy: indentation.count + markers.count)
        let titleRange = trimmedHeadingTitle(in: markdown, range: markerEnd..<lineRange.upperBound)
        var closingStart = titleRange.upperBound
        while closingStart > titleRange.lowerBound, markdown[markdown.index(before: closingStart)] == "#" {
            closingStart = markdown.index(before: closingStart)
        }
        let hasClosingHashes = closingStart < titleRange.upperBound
            && (closingStart == titleRange.lowerBound
                || markdown[markdown.index(before: closingStart)].isHorizontalHeadingWhitespace)
        let contentRange = hasClosingHashes
            ? trimmedHeadingTitle(in: markdown, range: titleRange.lowerBound..<closingStart)
            : titleRange
        let leadingSeparator = contentRange.lowerBound == markerEnd ? " " : ""
        let trailingSeparator = hasClosingHashes && contentRange.isEmpty ? " " : ""
        return String(markdown[..<contentRange.lowerBound]) + leadingSeparator
            + duplicatedTitle(String(markdown[contentRange])) + trailingSeparator
            + String(markdown[contentRange.upperBound...])
    }

    private func trimmedHeadingTitle(in markdown: String, range: Range<String.Index>) -> Range<String.Index> {
        var start = range.lowerBound
        var end = range.upperBound
        while start < end, markdown[start].isHorizontalHeadingWhitespace {
            start = markdown.index(after: start)
        }
        while end > start, markdown[markdown.index(before: end)].isHorizontalHeadingWhitespace {
            end = markdown.index(before: end)
        }
        return start..<end
    }

    private func replacingDuplicatedTitle(in markdown: String, range: Range<String.Index>) -> String {
        String(markdown[..<range.lowerBound]) + duplicatedTitle(String(markdown[range]))
            + String(markdown[range.upperBound...])
    }

    private func duplicatedTitle(_ title: String) -> String {
        guard !title.isEmpty else {
            return String(localized: .emptyDuplicatedNoteTitle)
        }
        return String(
            localized: "duplicatedNoteTitle",
            defaultValue: "\(title) Copy",
            comment: "Title of a duplicated note; the placeholder is the original title."
        )
    }

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

private extension Character {
    var isMarkdownLineEnding: Bool {
        self == "\n" || self == "\r" || self == "\r\n"
    }

    var isHorizontalHeadingWhitespace: Bool {
        self == " " || self == "\t"
    }
}

private extension JSONEncoder {
    static var notra: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
