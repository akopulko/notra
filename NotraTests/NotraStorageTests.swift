import Foundation
import ImageIO
@testable import Notra
import Testing

@MainActor
/// Verifies TextBundle creation, metadata, assets, previews, and repository round trips.
struct NotraStorageTests {
    @Test func createsSpecTextBundle() throws {
        let repository = try makeRepository()
        let note = try repository.createNote()

        #expect(note.url.pathExtension == "textbundle")
        #expect(FileManager.default.fileExists(
            atPath: note.url.appendingPathComponent("info.json").path(percentEncoded: false)
        ))
        #expect(FileManager.default.fileExists(
            atPath: note.url.appendingPathComponent("text.markdown").path(percentEncoded: false)
        ))
        #expect(FileManager.default.fileExists(
            atPath: note.url.appendingPathComponent("assets").path(percentEncoded: false)
        ))

        let infoData = try Data(contentsOf: note.url.appendingPathComponent("info.json"))
        let info = try JSONDecoder().decode(TextBundleInfo.self, from: infoData)
        #expect(info.version == 2)
        #expect(info.type == TextBundleInfo.markdownType)
    }

    @Test func createsUUIDNamedTextBundle() throws {
        let repository = try makeRepository()
        let note = try repository.createNote()
        let filename = note.url.deletingPathExtension().lastPathComponent

        #expect(UUID(uuidString: filename) != nil)
    }

    @Test func createsEmptyMarkdownBody() throws {
        let repository = try makeRepository()
        let note = try repository.createNote()

        #expect(note.markdown.isEmpty)
        #expect(note.createdAt != .distantPast)
    }

    @Test func createsMarkdownBodyFromInitialContent() throws {
        let repository = try makeRepository()
        let note = try repository.createNote(initialMarkdown: "# ")

        #expect(note.markdown == "# ")
    }

    @Test func importsJPEGAssetWithSpecReferenceAndPreservesMetadata() throws {
        let repository = try makeRepository()
        let note = try repository.createNote()
        let infoURL = note.url.appendingPathComponent(TextBundleNoteRepository.infoFilename)
        let originalInfo = try Data(contentsOf: infoURL)

        let firstAsset = try repository.importImage(
            data: onePixelPNGData,
            originalFilename: "holiday.png",
            into: note.url
        )
        let secondAsset = try repository.importImage(
            data: onePixelPNGData,
            originalFilename: "holiday.png",
            into: note.url
        )
        let firstURL = firstAsset.url
        let secondURL = secondAsset.url

        #expect(firstAsset.source == "assets/holiday.jpg")
        #expect(secondAsset.source == "assets/holiday%202.jpg")
        #expect(firstAsset.kind == .image)
        #expect(secondAsset.kind == .image)
        #expect(firstAsset.source != secondAsset.source)
        #expect(FileManager.default.fileExists(atPath: firstURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: secondURL.path(percentEncoded: false)))
        #expect(CGImageSourceCreateWithURL(firstURL as CFURL, nil) != nil)
        #expect(try Data(contentsOf: infoURL) == originalInfo)
    }

    @Test func listsAndDeletesImageAttachmentsWithinAssetsFolder() throws {
        let repository = try makeRepository()
        let note = try repository.createNote()
        let firstAsset = try repository.importImage(data: onePixelPNGData, into: note.url)
        let secondAsset = try repository.importImage(data: onePixelPNGData, into: note.url)
        let firstURL = firstAsset.url
        let secondURL = secondAsset.url

        let attachments = try repository.assetURLs(in: note.url)
        let expectedAttachments = [firstURL, secondURL]
            .map(\.notraCanonicalFileURL)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(attachments == expectedAttachments)

        try repository.deleteAttachment(firstURL, from: note.url)

        #expect(!FileManager.default.fileExists(atPath: firstURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: secondURL.path(percentEncoded: false)))
    }

    @Test func importsNonImageAttachmentWithOriginalFilenameAndCollisionSuffix() throws {
        let repository = try makeRepository()
        let note = try repository.createNote()
        let sourceURL = try makeSourceFile(named: "report.pdf", data: Data("report".utf8))

        let firstAsset = try repository.importAttachment(
            from: sourceURL,
            into: note.url,
            maximumByteCount: 100
        )
        let secondAsset = try repository.importAttachment(
            from: sourceURL,
            into: note.url,
            maximumByteCount: 100
        )

        #expect(firstAsset.source == "assets/report.pdf")
        #expect(secondAsset.source == "assets/report%202.pdf")
        #expect(firstAsset.kind == .attachment)
        #expect(secondAsset.kind == .attachment)
        #expect(try Data(contentsOf: firstAsset.url) == Data("report".utf8))
        #expect(try Data(contentsOf: secondAsset.url) == Data("report".utf8))
    }

    @Test func acceptsAttachmentExactlyAtConfiguredLimit() throws {
        let repository = try makeRepository()
        let note = try repository.createNote()
        let sourceURL = try makeSourceFile(named: "limit.bin", data: Data(repeating: 1, count: 4))

        let asset = try repository.importAttachment(
            from: sourceURL,
            into: note.url,
            maximumByteCount: 4
        )

        #expect(asset.source == "assets/limit.bin")
    }

    @Test func rejectsAttachmentExceedingConfiguredLimit() throws {
        let repository = try makeRepository()
        let note = try repository.createNote()
        let sourceURL = try makeSourceFile(named: "large.bin", data: Data(repeating: 1, count: 5))

        #expect(throws: NoteRepositoryError.attachmentTooLarge(filename: "large.bin", byteCount: 5, limit: 4)) {
            try repository.importAttachment(
                from: sourceURL,
                into: note.url,
                maximumByteCount: 4
            )
        }
    }

    @Test func rejectsAttachmentDeletionOutsideAssetsFolder() throws {
        let repository = try makeRepository()
        let note = try repository.createNote()
        let outsideURL = note.url.appendingPathComponent("outside.jpg")
        try onePixelPNGData.write(to: outsideURL)

        #expect(throws: NoteRepositoryError.invalidAttachment) {
            try repository.deleteAttachment(outsideURL, from: note.url)
        }
        #expect(FileManager.default.fileExists(atPath: outsideURL.path(percentEncoded: false)))
    }

    @Test func noteSummaryIgnoresUnlinkedAssets() throws {
        let repository = try makeRepository()
        let note = try repository.createNote()
        _ = try repository.importImage(
            data: onePixelPNGData,
            originalFilename: "photo.png",
            into: note.url
        )

        let summary = try #require(try repository.listNotes().first { $0.url == note.url })

        #expect(summary.attachmentSummary == .empty)
    }

    @Test func noteSummaryShowsPaperclipForLinkedImage() throws {
        let repository = try makeRepository()
        var note = try repository.createNote()
        let asset = try repository.importImage(
            data: onePixelPNGData,
            originalFilename: "photo.png",
            into: note.url
        )
        note.markdown = "![Photo](\(asset.source))"
        try repository.save(note)

        let summary = try #require(try repository.listNotes().first { $0.url == note.url })

        #expect(summary.attachmentSummary.firstLinkedImageURL == asset.url.notraCanonicalFileURL)
        #expect(!summary.attachmentSummary.hasLinkedNonImageAttachment)
        #expect(summary.attachmentSummary.showsPaperclip)
    }

    @Test func noteSummaryUsesPaperclipForLinkedNonImageAttachment() throws {
        let repository = try makeRepository()
        var note = try repository.createNote()
        let sourceURL = try makeSourceFile(named: "report.pdf", data: Data("report".utf8))
        let asset = try repository.importAttachment(
            from: sourceURL,
            into: note.url,
            maximumByteCount: 100
        )
        note.markdown = "[Report](\(asset.source))"
        try repository.save(note)

        let summary = try #require(try repository.listNotes().first { $0.url == note.url })

        #expect(summary.attachmentSummary.firstLinkedImageURL == nil)
        #expect(summary.attachmentSummary.hasLinkedNonImageAttachment)
        #expect(summary.attachmentSummary.showsPaperclip)
    }

    @Test func noteSummaryShowsPaperclipForLinkedImageAndAttachment() throws {
        let repository = try makeRepository()
        var note = try repository.createNote()
        let imageAsset = try repository.importImage(
            data: onePixelPNGData,
            originalFilename: "photo.png",
            into: note.url
        )
        let sourceURL = try makeSourceFile(named: "report.pdf", data: Data("report".utf8))
        let fileAsset = try repository.importAttachment(
            from: sourceURL,
            into: note.url,
            maximumByteCount: 100
        )
        note.markdown = "![Photo](\(imageAsset.source))\n[Report](\(fileAsset.source))"
        try repository.save(note)

        let summary = try #require(try repository.listNotes().first { $0.url == note.url })

        #expect(summary.attachmentSummary.firstLinkedImageURL == imageAsset.url.notraCanonicalFileURL)
        #expect(summary.attachmentSummary.hasLinkedNonImageAttachment)
        #expect(summary.attachmentSummary.showsPaperclip)
    }

    @Test func noteSummaryIgnoresMissingLinkedAssets() throws {
        let repository = try makeRepository()
        var note = try repository.createNote()
        note.markdown = "![Missing](assets/missing.jpg)\n[Missing](assets/missing.pdf)"
        try repository.save(note)

        let summary = try #require(try repository.listNotes().first { $0.url == note.url })

        #expect(summary.attachmentSummary == .empty)
    }

    @Test func savesMarkdownRoundTrip() throws {
        let repository = try makeRepository()
        var note = try repository.createNote()
        note.markdown = "# Heading\n\nThis is **bold**."

        try repository.save(note)
        let loaded = try repository.loadNote(at: note.url)

        #expect(loaded.markdown == note.markdown)
    }

    @Test func readsAndWritesTagsInNotraMetadata() throws {
        let repository = try makeRepository()
        let note = try repository.createNote()
        let metadata = NoteMetadata(tags: [try #require(NoteTag("Swift")), try #require(NoteTag("work"))])

        try repository.updateNoteMetadata(metadata, for: note.url)
        let loadedMetadata = try repository.noteMetadata(at: note.url)

        #expect(loadedMetadata.tags.map(\.name) == ["Swift", "work"])
    }

    @Test func noteSummariesIncludeTagsFromMetadata() throws {
        let repository = try makeRepository()
        let note = try repository.createNote()
        let metadata = NoteMetadata(tags: [try #require(NoteTag("Swift")), try #require(NoteTag("work"))])

        try repository.updateNoteMetadata(metadata, for: note.url)

        let summary = try #require(try repository.listNotes().first)
        #expect(summary.tags.map(\.name) == ["Swift", "work"])
    }

    @Test func metadataPreventsDuplicateTagsCaseInsensitively() throws {
        let metadata = NoteMetadata(tags: [
            try #require(NoteTag("Swift")),
            try #require(NoteTag("swift")),
            try #require(NoteTag("SWIFT"))
        ])

        #expect(metadata.tags.map(\.name) == ["Swift"])
    }

    @Test func metadataUpdatePreservesUnknownInfoFields() throws {
        let repository = try makeRepository()
        let note = try repository.createNote()
        let infoURL = note.url.appendingPathComponent(TextBundleNoteRepository.infoFilename)
        let customInfo: [String: Any] = [
            "version": 2,
            "type": TextBundleInfo.markdownType,
            "creatorIdentifier": "External.App",
            "External.App": ["custom": true],
            "app.notra.Notra": [
                "version": 1,
                "future": "keep"
            ]
        ]
        let originalData = try JSONSerialization.data(withJSONObject: customInfo, options: [.prettyPrinted])
        try originalData.write(to: infoURL)

        try repository.updateNoteMetadata(
            NoteMetadata(tags: [try #require(NoteTag("swift"))]),
            for: note.url
        )

        let data = try Data(contentsOf: infoURL)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let external = try #require(object["External.App"] as? [String: Any])
        let notra = try #require(object["app.notra.Notra"] as? [String: Any])

        #expect(object["creatorIdentifier"] as? String == "External.App")
        #expect(external["custom"] as? Bool == true)
        #expect(notra["future"] as? String == "keep")
        #expect(notra["tags"] as? [String] == ["swift"])
    }

    @Test func saveUpdatesModifiedDate() throws {
        let repository = try makeRepository()
        let note = try repository.createNote()
        let original = try repository.loadNote(at: note.url)
        var updated = original
        updated.markdown = "# Updated content"

        try repository.save(updated)
        let reloaded = try repository.loadNote(at: note.url)

        #expect(reloaded.modifiedAt >= original.modifiedAt)
        let summary = try #require(
            try repository.listNotes().first { $0.url == note.url }
        )
        #expect(summary.modifiedAt >= original.modifiedAt)
    }

    @Test func localStorageDescriptionMatchesPlatform() throws {
        let repository = try makeRepository()

        #if os(iOS)
            #expect(repository.storageDescription == "On My iPhone / Notra")
        #else
            #expect(repository.storageDescription == "On My Mac / Notra")
        #endif
    }

    @Test func iCloudStorageDescriptionMatchesFilesLocation() {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = TextBundleNoteRepository(rootURL: rootURL, isUsingICloud: true)

        #expect(repository.storageDescription == "iCloud Drive / Notra")
    }

    @Test func listsNotesWithoutExtensions() throws {
        let repository = try makeRepository()
        let firstURL = try makeTextBundle(named: "First", markdown: "First content", in: repository.rootURL)
        let secondURL = try makeTextBundle(named: "Second", markdown: "Second content", in: repository.rootURL)

        let notes = try repository.listNotes()

        #expect(notes.map(\.url).contains(firstURL))
        #expect(notes.map(\.url).contains(secondURL))
        #expect(notes.allSatisfy { $0.createdAt != .distantPast })
    }

    @Test func loadsExistingHumanNamedBundleWithoutRenamingIt() throws {
        let repository = try makeRepository()
        let url = try makeTextBundle(named: "Human Name", markdown: "Existing content", in: repository.rootURL)

        let note = try repository.loadNote(at: url)

        #expect(note.url.lastPathComponent == "Human Name.textbundle")
        #expect(note.markdown == "Existing content")
    }

    @Test func derivesPreviewFromFirstNonEmptyPlainMarkdownLine() throws {
        let repository = try makeRepository()
        _ = try makeTextBundle(
            named: "Preview Source",
            markdown: "\n\n## **Readable** [Title](https://example.com)\n- Second line\n> Third line\nFourth line",
            in: repository.rootURL
        )

        let summary = try #require(try repository.listNotes().first)

        #expect(summary.previewText == "Readable Title\nSecond line\nThird line")
        #expect(summary.previewFirstLineIsHeading)
    }

    @Test func skipsLeadingMarkdownTableWhenDerivingPreview() throws {
        let repository = try makeRepository()
        _ = try makeTextBundle(
            named: "Table Preview Source",
            markdown: """
            | Name | Value |
            | :--- | ---: |
            | One | 1 |
            | Two | 2 |

            Readable title
            Second line
            Third line
            """,
            in: repository.rootURL
        )

        let summary = try #require(try repository.listNotes().first)

        #expect(summary.previewText == "Readable title\nSecond line\nThird line")
    }

    @Test func keepsNonTablePipeTextInPreview() throws {
        let repository = try makeRepository()
        _ = try makeTextBundle(
            named: "Pipe Preview Source",
            markdown: "Text with | a pipe\nSecond line",
            in: repository.rootURL
        )

        let summary = try #require(try repository.listNotes().first)

        #expect(summary.previewText == "Text with | a pipe\nSecond line")
    }

    @Test func skipsEmbeddedMarkdownTableWhenDerivingPreview() throws {
        let repository = try makeRepository()
        _ = try makeTextBundle(
            named: "Embedded Table Preview Source",
            markdown: """
            First line
            | Name | Value |
            | --- | --- |
            | One | 1 |
            Second line
            Third line
            """,
            in: repository.rootURL
        )

        let summary = try #require(try repository.listNotes().first)

        #expect(summary.previewText == "First line\nSecond line\nThird line")
    }

    @Test func skipsMarkdownTableAfterHeadingWhenDerivingPreview() throws {
        let repository = try makeRepository()
        _ = try makeTextBundle(
            named: "Heading Table Preview Source",
            markdown: """
            # Readable title
            | Name | Value |
            | --- | --- |
            | One | 1 |
            Readable body
            Another line
            """,
            in: repository.rootURL
        )

        let summary = try #require(try repository.listNotes().first)

        #expect(summary.previewText == "Readable title\nReadable body\nAnother line")
        #expect(summary.previewFirstLineIsHeading)
    }

    @Test func emptyNotesUsePlaceholderPreview() throws {
        let repository = try makeRepository()
        _ = try makeTextBundle(named: "Empty", markdown: "\n \n", in: repository.rootURL)

        let summary = try #require(try repository.listNotes().first)

        #expect(summary.previewText == NoteSummary.emptyPreviewText)
        #expect(!summary.previewFirstLineIsHeading)
    }

    @Test func summariesKeepOnlyPreviewData() throws {
        let repository = try makeRepository()
        _ = try makeTextBundle(
            named: "Search Source",
            markdown: "Preview line\n\nHidden searchable body",
            in: repository.rootURL
        )

        let summary = try #require(try repository.listNotes().first)

        #expect(summary.previewText == "Preview line\nHidden searchable body")
        #expect(!summary.previewFirstLineIsHeading)
    }

    private func makeRepository() throws -> TextBundleNoteRepository {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return TextBundleNoteRepository(rootURL: rootURL)
    }

    private var onePixelPNGData: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    }

    private func makeSourceFile(named filename: String, data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(filename)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    private func makeTextBundle(named name: String, markdown: String, in rootURL: URL) throws -> URL {
        let bundleURL = rootURL
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathExtension(TextBundleNoteRepository.bundleExtension)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: bundleURL.appendingPathComponent(TextBundleNoteRepository.assetsFolder, isDirectory: true),
            withIntermediateDirectories: true
        )
        let infoData = try JSONEncoder().encode(TextBundleInfo())
        try infoData.write(to: bundleURL.appendingPathComponent(TextBundleNoteRepository.infoFilename))
        try markdown.write(
            to: bundleURL.appendingPathComponent(TextBundleNoteRepository.textFilename),
            atomically: true,
            encoding: .utf8
        )
        return bundleURL
    }
}
