import Foundation
@testable import Notra
import Testing

/// Verifies note statistics, metadata projection, and human-readable byte formatting.
struct NoteInfoTests {
    @Test func emptyMarkdownHasZeroStatistics() {
        let statistics = NoteStatistics(markdown: "")

        #expect(statistics.wordCount == 0)
        #expect(statistics.characterCount == 0)
        #expect(statistics.lineCount == 0)
        #expect(statistics.readingTimeMinutes == 0)
    }

    @Test func statisticsIgnoreBlankLinesAndCountUnicodeCharacters() {
        let statistics = NoteStatistics(markdown: "  \nOne café\n\nTwo\n")

        #expect(statistics.wordCount == 3)
        #expect(statistics.characterCount == 17)
        #expect(statistics.lineCount == 2)
        #expect(statistics.readingTimeMinutes == 1)
    }

    @Test func readingTimeRoundsUpToTheNextMinute() {
        let twoHundredWords = Array(repeating: "word", count: 200).joined(separator: " ")
        let twoHundredAndOneWords = Array(repeating: "word", count: 201).joined(separator: " ")

        #expect(NoteStatistics(markdown: twoHundredWords).readingTimeMinutes == 1)
        #expect(NoteStatistics(markdown: twoHundredAndOneWords).readingTimeMinutes == 2)
    }

    @Test func noteInfoUsesTextBundleMetadata() {
        let summary = NoteSummary(
            url: URL(fileURLWithPath: "/tmp/example.textbundle"),
            previewText: "Example",
            createdAt: Date(timeIntervalSince1970: 100),
            modifiedAt: Date(timeIntervalSince1970: 200)
        )
        let info = NoteInfo(
            summary: summary,
            markdown: "café",
            location: "On My Phone/Notra",
            byteCount: 1234
        )

        #expect(info.location == "On My Phone/Notra")
        #expect(info.filename == summary.url.lastPathComponent)
        #expect(info.byteCount == 1234)
        #expect(info.createdAt == summary.createdAt)
        #expect(info.modifiedAt == summary.modifiedAt)
    }

    @Test func bundleSizeIncludesAssets() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = TextBundleNoteRepository(rootURL: rootURL)
        let note = try repository.createNote()
        let initialSize = repository.totalBundleSize(at: note.url)
        let assetURL = note.url
            .appendingPathComponent(TextBundleNoteRepository.assetsFolder, isDirectory: true)
            .appendingPathComponent("example.bin")
        let assetData = Data(repeating: 1, count: 32)
        try assetData.write(to: assetURL)

        #expect(repository.totalBundleSize(at: note.url) == initialSize + Int64(assetData.count))
    }

    @Test func noteLocationDescriptionUsesStorageKind() {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localRepository = TextBundleNoteRepository(rootURL: rootURL)
        let iCloudRepository = TextBundleNoteRepository(rootURL: rootURL, isUsingICloud: true)

        #expect(iCloudRepository.noteLocationDescription == "iCloud/Notra")
        #if os(iOS)
        #expect(localRepository.noteLocationDescription == "On My Phone/Notra")
        #else
        #expect(localRepository.noteLocationDescription == "On My Mac/Notra")
        #endif
    }
}
