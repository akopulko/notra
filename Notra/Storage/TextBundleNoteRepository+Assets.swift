import Foundation
import ImageIO
import UniformTypeIdentifiers

extension TextBundleNoteRepository {
    /// Copies a file into `assets`, routing images through the canonical JPEG encoder.
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

    /// Decodes arbitrary image data and stores a uniquely named JPEG asset in the bundle.
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

    /// Returns visible regular files in the bundle's assets directory in stable filename order.
    nonisolated func assetURLs(in noteURL: URL) throws -> [URL] {
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

    /// Sums regular-file sizes recursively for the inspector's bundle-size statistic.
    nonisolated func totalBundleSize(at bundleURL: URL) -> Int64 {
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

    /// Validates that the URL is a direct asset of this bundle before deleting it.
    func deleteAttachment(_ attachmentURL: URL, from noteURL: URL) throws {
        let validatedURL = try validatedAttachmentURL(attachmentURL, in: noteURL)
        try FileManager.default.removeItem(at: validatedURL)
        AppLog.info("Deleted attachment; name=\(validatedURL.lastPathComponent)")
    }

    /// Ensures the assets directory exists before an import writes into it.
    private func preparedAssetsURL(in noteURL: URL) throws -> URL {
        let assetsURL = noteURL.appendingPathComponent(Self.assetsFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        return assetsURL
    }

    /// Reads a source file size using resource values with an attributes fallback.
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

    /// Rejects imports before copying or decoding when they exceed the user's configured limit.
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

    /// Sanitizes an imported name and appends a numeric suffix on case-insensitive collisions.
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

    /// Removes path separators while retaining a readable attachment filename.
    private func sanitizedFilename(_ filename: String) -> String {
        let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmedFilename.isEmpty ? "attachment" : trimmedFilename
        let sanitized = fallback
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return sanitized == "." || sanitized == ".." ? "attachment" : sanitized
    }

    /// Replaces the source extension so image imports advertise their canonical JPEG format.
    private func jpegFilename(for originalFilename: String) -> String {
        let fileURL = URL(fileURLWithPath: originalFilename)
        let baseName = fileURL.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(baseName.isEmpty ? "image" : baseName).jpg"
    }

    /// Prevents deletion outside the selected bundle's direct assets directory.
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
}
