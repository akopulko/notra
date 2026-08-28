import Foundation
import ImageIO
import Markdown
import UniformTypeIdentifiers

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

struct TextBundleNoteRepository {
    nonisolated static let bundleExtension = "textbundle"
    nonisolated static let textFilename = "text.markdown"
    nonisolated static let infoFilename = "info.json"
    nonisolated static let assetsFolder = "assets"
    nonisolated static let appMetadataKey = "app.notra.Notra"

    let rootURL: URL
    let isUsingICloud: Bool

    init(rootURL: URL, isUsingICloud: Bool = false) {
        self.rootURL = rootURL
        self.isUsingICloud = isUsingICloud
    }

    static func production(fileManager: FileManager = .default) -> TextBundleNoteRepository {
        let iCloudURL = iCloudContainerIdentifier.flatMap(fileManager.url(forUbiquityContainerIdentifier:))
        if let iCloudURL {
            let documentsURL = iCloudURL.appendingPathComponent("Documents", isDirectory: true)
            let repository = TextBundleNoteRepository(rootURL: documentsURL, isUsingICloud: true)
            do {
                try repository.prepareStorage()
                AppLog.info("Using iCloud note storage")
                return repository
            } catch {
                AppLog.error("Failed to prepare iCloud note storage: \(error.localizedDescription)")
            }
        } else if iCloudContainerIdentifier != nil {
            AppLog.warning("iCloud note storage is configured but unavailable; using local note storage")
        }

        let rootURL = localRootURL(fileManager: fileManager) ?? fileManager.temporaryDirectory
        let repository = TextBundleNoteRepository(rootURL: rootURL, isUsingICloud: false)

        do {
            try repository.prepareStorage()
            AppLog.info("Using local note storage")
        } catch {
            AppLog.error("Failed to prepare note storage: \(error.localizedDescription)")
        }

        return repository
    }

    private static var iCloudContainerIdentifier: String? {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "NotraICloudContainerIdentifier"
        ) as? String else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static func localRootURL(fileManager: FileManager) -> URL? {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        #if os(iOS)
        return documentsURL
        #else
        return documentsURL.appendingPathComponent("Notra", isDirectory: true)
        #endif
    }

    func prepareStorage() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

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

    func listNotes() throws -> [NoteSummary] {
        try prepareStorage()

        let urls = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return try urls
            .filter { $0.pathExtension == Self.bundleExtension }
            .map { url in
                let createdAt = try url.resourceValues(forKeys: [.creationDateKey])
                    .creationDate ?? .distantPast
                let markdown = try markdownContent(in: url)
                let preview = Self.preview(for: markdown)
                let attachmentSummary = try attachmentSummary(for: url, markdown: markdown)
                return try NoteSummary(
                    url: url,
                    previewText: preview.text,
                    previewFirstLineIsHeading: preview.firstLineIsHeading,
                    attachmentSummary: attachmentSummary,
                    createdAt: createdAt,
                    modifiedAt: modifiedDate(of: url)
                )
            }
    }

    func loadNote(at url: URL) throws -> Note {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw NoteRepositoryError.noteNotFound
        }

        let textURL = url.appendingPathComponent(Self.textFilename)
        let markdown = try String(contentsOf: textURL, encoding: .utf8)
        let metadata = (try? noteMetadata(at: url)) ?? NoteMetadata()
        let createdAt = try url.resourceValues(forKeys: [.creationDateKey])
            .creationDate ?? .distantPast
        _ = Document(parsing: markdown)

        return try Note(
            url: url,
            markdown: markdown,
            metadata: metadata,
            createdAt: createdAt,
            modifiedAt: modifiedDate(of: url)
        )
    }

    func createNote() throws -> Note {
        try prepareStorage()

        let bundleURL = try uniqueBundleURL()

        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: bundleURL.appendingPathComponent(Self.assetsFolder, isDirectory: true),
            withIntermediateDirectories: true
        )

        let infoData = try JSONEncoder.notra.encode(TextBundleInfo())
        try infoData.write(to: bundleURL.appendingPathComponent(Self.infoFilename), options: .atomic)

        let markdown = ""
        try markdown.write(to: bundleURL.appendingPathComponent(Self.textFilename), atomically: true, encoding: .utf8)
        return try loadNote(at: bundleURL)
    }

    func save(_ note: Note) throws {
        guard FileManager.default.fileExists(atPath: note.url.path(percentEncoded: false)) else {
            throw NoteRepositoryError.noteNotFound
        }

        _ = Document(parsing: note.markdown)
        try note.markdown.write(
            to: note.url.appendingPathComponent(Self.textFilename),
            atomically: true,
            encoding: .utf8
        )
    }

    func noteMetadata(at noteURL: URL) throws -> NoteMetadata {
        let infoURL = noteURL.appendingPathComponent(Self.infoFilename)
        guard FileManager.default.fileExists(atPath: infoURL.path(percentEncoded: false)) else {
            return NoteMetadata()
        }

        let data = try Data(contentsOf: infoURL)
        let info = try JSONDecoder().decode(TextBundleInfo.self, from: data)
        return NoteMetadata(tags: info.notra.tags)
    }

    func updateNoteMetadata(_ metadata: NoteMetadata, for noteURL: URL) throws {
        guard FileManager.default.fileExists(atPath: noteURL.path(percentEncoded: false)) else {
            throw NoteRepositoryError.noteNotFound
        }

        let infoURL = noteURL.appendingPathComponent(Self.infoFilename)
        var root = try metadataJSONObject(at: infoURL)
        var appMetadata = root[Self.appMetadataKey] as? [String: Any] ?? [:]

        appMetadata["version"] = appMetadata["version"] ?? 1
        appMetadata["tags"] = metadata.tags.map(\.name)
        root[Self.appMetadataKey] = appMetadata
        root["version"] = root["version"] ?? 2
        root["type"] = root["type"] ?? TextBundleInfo.markdownType
        root["creatorIdentifier"] = root["creatorIdentifier"] ?? Self.appMetadataKey

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: infoURL, options: .atomic)
    }

    func importAttachment(
        from sourceURL: URL,
        into noteURL: URL,
        maximumByteCount: Int64
    ) throws -> ImportedTextBundleAsset {
        let byteCount = try fileSize(at: sourceURL)
        try validateAttachmentSize(
            filename: sourceURL.lastPathComponent,
            byteCount: byteCount,
            maximumByteCount: maximumByteCount
        )

        let contentType = try sourceURL.resourceValues(forKeys: [.contentTypeKey]).contentType
            ?? UTType(filenameExtension: sourceURL.pathExtension)
        let kind = TextBundleAssetKind(contentType: contentType, filename: sourceURL.lastPathComponent)

        if kind.isImage {
            let data = try Data(contentsOf: sourceURL)
            return try importImage(
                data: data,
                originalFilename: sourceURL.lastPathComponent,
                into: noteURL
            )
        }

        let assetsURL = try preparedAssetsURL(in: noteURL)
        let filename = try uniqueAssetFilename(
            preferredName: sourceURL.lastPathComponent,
            in: assetsURL
        )
        let targetURL = assetsURL.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: sourceURL, to: targetURL)
        let source = "\(Self.assetsFolder)/\(filename.percentEncodedMarkdownPathComponent)"
        AppLog.info("Copied attachment asset; source=\(source); bytes=\(byteCount)")
        return ImportedTextBundleAsset(
            url: targetURL,
            source: source,
            kind: .attachment,
            filename: filename
        )
    }

    func importImage(
        data: Data,
        originalFilename: String = "image",
        into noteURL: URL,
        jpegQuality: CGFloat = 0.9
    ) throws -> ImportedTextBundleAsset {
        AppLog.info(
            """
            Preparing image import; inputBytes=\(data.count); \
            originalName=\(originalFilename); note=\(noteURL.lastPathComponent)
            """
        )
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            AppLog.warning("Image import failed because the image data could not be decoded")
            throw NoteRepositoryError.invalidImageData
        }

        let encodedData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encodedData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        )
        else {
            AppLog.error("Image import failed because the JPEG destination could not be created")
            throw NoteRepositoryError.imageEncodingFailed
        }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            AppLog.error("Image import failed because JPEG encoding could not be finalized")
            throw NoteRepositoryError.imageEncodingFailed
        }
        AppLog.info("Encoded imported image as JPEG; outputBytes=\(encodedData.length)")

        let assetsURL = try preparedAssetsURL(in: noteURL)
        let filename = try uniqueAssetFilename(
            preferredName: jpegFilename(for: originalFilename),
            in: assetsURL
        )
        let assetURL = assetsURL.appendingPathComponent(filename)

        try (encodedData as Data).write(to: assetURL, options: .atomic)
        let source = "\(Self.assetsFolder)/\(filename.percentEncodedMarkdownPathComponent)"
        AppLog.info("Wrote imported image asset; source=\(source)")
        return ImportedTextBundleAsset(
            url: assetURL,
            source: source,
            kind: .image,
            filename: filename
        )
    }

    func assetURLs(in noteURL: URL) throws -> [URL] {
        let assetsURL = noteURL.appendingPathComponent(Self.assetsFolder, isDirectory: true)
        guard FileManager.default.fileExists(atPath: assetsURL.path(percentEncoded: false)) else {
            return []
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: assetsURL,
            includingPropertiesForKeys: [.contentTypeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return try urls
            .filter { url in
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                return values.isRegularFile == true
            }
            .map(\.notraCanonicalFileURL)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func totalBundleSize(at bundleURL: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: bundleURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true
            else {
                continue
            }
            totalSize += Int64(values.fileSize ?? 0)
        }
        return totalSize
    }

    func deleteAttachment(_ attachmentURL: URL, from noteURL: URL) throws {
        let validatedURL = try validatedAttachmentURL(attachmentURL, in: noteURL)
        try FileManager.default.removeItem(at: validatedURL)
        AppLog.info("Deleted attachment; name=\(validatedURL.lastPathComponent)")
    }

    func delete(_ summary: NoteSummary) throws {
        guard FileManager.default.fileExists(atPath: summary.url.path(percentEncoded: false)) else {
            throw NoteRepositoryError.noteNotFound
        }
        try FileManager.default.removeItem(at: summary.url)
    }
}

private extension TextBundleNoteRepository {
    private func attachmentSummary(for noteURL: URL, markdown: String) throws -> NoteAttachmentSummary {
        let assetBaseURL = noteURL.appendingPathComponent(Self.assetsFolder, isDirectory: true)
        let linkedURLs = MarkdownAttachmentReferences.linkedURLs(in: markdown, assetBaseURL: assetBaseURL)
        guard !linkedURLs.isEmpty else {
            return .empty
        }

        var firstLinkedImageURL: URL?
        var hasLinkedNonImageAttachment = false
        for assetURL in try assetURLs(in: noteURL) {
            let standardizedURL = assetURL.notraCanonicalFileURL
            guard linkedURLs.contains(standardizedURL) else {
                continue
            }

            let contentType = try assetURL.resourceValues(forKeys: [.contentTypeKey]).contentType
                ?? UTType(filenameExtension: assetURL.pathExtension)
            switch TextBundleAssetKind(contentType: contentType, filename: assetURL.lastPathComponent) {
            case .image where firstLinkedImageURL == nil:
                firstLinkedImageURL = standardizedURL
            case .attachment:
                hasLinkedNonImageAttachment = true
            default:
                break
            }

            if firstLinkedImageURL != nil, hasLinkedNonImageAttachment {
                break
            }
        }

        return NoteAttachmentSummary(
            firstLinkedImageURL: firstLinkedImageURL,
            hasLinkedNonImageAttachment: hasLinkedNonImageAttachment
        )
    }

    private func metadataJSONObject(at infoURL: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: infoURL.path(percentEncoded: false)) else {
            return [:]
        }

        let data = try Data(contentsOf: infoURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NoteRepositoryError.invalidMetadata
        }
        return object
    }

    private func modifiedDate(of bundleURL: URL) throws -> Date {
        let textURL = bundleURL.appendingPathComponent(Self.textFilename)
        let textValues = try textURL.resourceValues(forKeys: [.contentModificationDateKey])
        if let modifiedAt = textValues.contentModificationDate {
            return modifiedAt
        }
        let bundleValues = try bundleURL.resourceValues(forKeys: [.contentModificationDateKey])
        return bundleValues.contentModificationDate ?? .distantPast
    }

    private func markdownContent(in bundleURL: URL) throws -> String {
        let textURL = bundleURL.appendingPathComponent(Self.textFilename)
        return try String(contentsOf: textURL, encoding: .utf8)
    }

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

    private func preparedAssetsURL(in noteURL: URL) throws -> URL {
        let assetsURL = noteURL.appendingPathComponent(Self.assetsFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        return assetsURL
    }

    private func fileSize(at url: URL) throws -> Int64 {
        if let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            return Int64(fileSize)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        guard let size = attributes[.size] as? NSNumber else {
            throw NoteRepositoryError.invalidAttachment
        }
        return size.int64Value
    }

    private func validateAttachmentSize(
        filename: String,
        byteCount: Int64,
        maximumByteCount: Int64
    ) throws {
        guard byteCount <= maximumByteCount else {
            AppLog.warning(
                """
                Rejecting oversized attachment; name=\(filename); \
                bytes=\(byteCount); limit=\(maximumByteCount)
                """
            )
            throw NoteRepositoryError.attachmentTooLarge(
                filename: filename,
                byteCount: byteCount,
                limit: maximumByteCount
            )
        }
    }

    private func uniqueAssetFilename(preferredName: String, in assetsURL: URL) throws -> String {
        let sanitizedName = sanitizedFilename(preferredName)
        let existingNames = try Set(FileManager.default.contentsOfDirectory(atPath: assetsURL.path(percentEncoded: false))
            .map { $0.lowercased() })

        guard existingNames.contains(sanitizedName.lowercased()) else {
            return sanitizedName
        }

        let fileURL = URL(fileURLWithPath: sanitizedName)
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = fileURL.pathExtension

        for suffix in 2..<10000 {
            let candidate = if fileExtension.isEmpty {
                "\(baseName) \(suffix)"
            } else {
                "\(baseName) \(suffix).\(fileExtension)"
            }

            if !existingNames.contains(candidate.lowercased()) {
                return candidate
            }
        }

        throw NoteRepositoryError.storageUnavailable
    }

    private func sanitizedFilename(_ filename: String) -> String {
        let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmedFilename.isEmpty ? "attachment" : trimmedFilename
        let sanitized = fallback
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return sanitized == "." || sanitized == ".." ? "attachment" : sanitized
    }

    private func jpegFilename(for originalFilename: String) -> String {
        let fileURL = URL(fileURLWithPath: originalFilename)
        let baseName = fileURL.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(baseName.isEmpty ? "image" : baseName).jpg"
    }

    private func validatedAttachmentURL(_ attachmentURL: URL, in noteURL: URL) throws -> URL {
        let assetsURL = noteURL
            .appendingPathComponent(Self.assetsFolder, isDirectory: true)
            .notraCanonicalFileURL
        let resolvedAttachmentURL = attachmentURL.notraCanonicalFileURL
        let values = try resolvedAttachmentURL.resourceValues(forKeys: [.isRegularFileKey])

        guard resolvedAttachmentURL.deletingLastPathComponent() == assetsURL,
              values.isRegularFile == true
        else {
            throw NoteRepositoryError.invalidAttachment
        }

        return resolvedAttachmentURL
    }

    static func previewText(for markdown: String) -> String {
        preview(for: markdown).text
    }

    static func preview(for markdown: String) -> NotePreview {
        let lines = previewSourceLines(from: markdown)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let previewLines = lines
            .prefix(3)
            .map { line in
                NotePreview.Line(text: plainText(fromMarkdownLine: line), isHeading: isMarkdownHeading(line))
            }
            .filter { !$0.text.isEmpty }

        guard !previewLines.isEmpty else {
            return NotePreview(text: NoteSummary.emptyPreviewText, firstLineIsHeading: false)
        }

        return NotePreview(
            text: previewLines.map(\.text).joined(separator: "\n"),
            firstLineIsHeading: previewLines.first?.isHeading ?? false
        )
    }

    private static func previewSourceLines(from markdown: String) -> [String] {
        let lines = markdown.components(separatedBy: .newlines)
        var previewLines: [String] = []
        var index = 0

        while index < lines.count {
            guard isTableHeader(lines[index]),
                  index + 1 < lines.count,
                  let columnCount = tableColumnCount(in: lines[index + 1]),
                  tableCellCount(in: lines[index]) == columnCount
            else {
                previewLines.append(lines[index])
                index += 1
                continue
            }

            index += 2
            while index < lines.count, isTableRow(lines[index]) {
                index += 1
            }
        }

        return previewLines
    }

    private static func isTableHeader(_ line: String) -> Bool {
        line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func tableColumnCount(in delimiter: String) -> Int? {
        let cells = tableCells(in: delimiter)
        guard !cells.isEmpty,
              cells.allSatisfy({
                  $0.trimmingCharacters(in: .whitespaces)
                      .range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
              })
        else {
            return nil
        }

        return cells.count
    }

    private static func tableCellCount(in row: String) -> Int {
        tableCells(in: row).count
    }

    private static func tableCells(in line: String) -> [Substring] {
        var row = line[...]
        if row.first == "|" {
            row.removeFirst()
        }
        if row.last == "|" {
            row.removeLast()
        }
        return row.split(separator: "|", omittingEmptySubsequences: false)
    }

    private static func plainText(fromMarkdownLine line: String) -> String {
        line
            .replacingOccurrences(
                of: #"^\s{0,3}#{1,6}\s+"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s+#{1,6}\s*$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"^\s{0,3}>\s?"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"^\s*([-*+]|\d+[.)])\s+"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"^\s*\[[ xX]\]\s+"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"!\[([^\]]*)\]\([^)]+\)"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\[([^\]]+)\]\([^)]+\)"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"[*_`~]+"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isMarkdownHeading(_ line: String) -> Bool {
        line.range(
            of: #"^\s{0,3}#{1,6}(\s|$)"#,
            options: .regularExpression
        ) != nil
    }
}

struct NotePreview: Equatable {
    struct Line: Equatable {
        let text: String
        let isHeading: Bool
    }

    let text: String
    let firstLineIsHeading: Bool
}

private extension JSONEncoder {
    static var notra: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
