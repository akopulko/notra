import Foundation

/// Derives display statistics from note text without retaining another copy of the document.
struct NoteStatistics: Equatable, Sendable {
    /// Reading-speed baseline used to round estimates up to whole minutes.
    static let wordsPerMinute = 200

    /// Number of words found in the Markdown body.
    let wordCount: Int
    /// Number of Swift characters in the Markdown body.
    let characterCount: Int
    /// Number of non-empty logical lines.
    let lineCount: Int
    /// Rounded-up reading estimate derived from `wordCount`.
    let readingTimeMinutes: Int

    init(markdown: String) {
        wordCount = Self.countWords(in: markdown)
        characterCount = markdown.count
        lineCount = Self.countLines(in: markdown)
        readingTimeMinutes = wordCount == 0 ? 0 : max(1, (wordCount + Self.wordsPerMinute - 1) / Self.wordsPerMinute)
    }

    private static func countWords(in markdown: String) -> Int {
        var count = 0
        markdown.enumerateSubstrings(
            in: markdown.startIndex..<markdown.endIndex,
            options: .byWords
        ) { _, _, _, _ in
            count += 1
        }
        return count
    }

    private static func countLines(in markdown: String) -> Int {
        markdown.split(whereSeparator: \.isNewline).count { line in
            !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// Combines note metadata, content statistics, storage location, and bundle size for the inspector.
struct NoteInfo: Equatable, Sendable {
    /// Derived content statistics for the selected note.
    let statistics: NoteStatistics
    /// Creation time read from the note bundle.
    let createdAt: Date
    /// Last modification time read from the note bundle.
    let modifiedAt: Date
    /// Human-readable local or iCloud location label.
    let location: String
    /// TextBundle filename shown in the inspector.
    let filename: String
    /// Total bytes occupied by the bundle and its assets.
    let byteCount: Int64

    init(summary: NoteSummary, markdown: String, location: String, byteCount: Int64) {
        statistics = NoteStatistics(markdown: markdown)
        createdAt = summary.createdAt
        modifiedAt = summary.modifiedAt
        self.location = location
        filename = summary.url.lastPathComponent
        self.byteCount = byteCount
    }
}
