import Foundation

/// Derives display statistics from note text without retaining another copy of the document.
struct NoteStatistics: Equatable, Sendable {
    /// Number of words found in the Markdown body.
    let wordCount: Int
    /// Number of Swift characters in the Markdown body.
    let characterCount: Int

    nonisolated init(markdown: String) {
        wordCount = Self.countWords(in: markdown)
        characterCount = markdown.count
    }

    private nonisolated static func countWords(in markdown: String) -> Int {
        var count = 0
        markdown.enumerateSubstrings(
            in: markdown.startIndex..<markdown.endIndex,
            options: .byWords
        ) { _, _, _, _ in
            count += 1
        }
        return count
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
    /// Canonical TextBundle URL used for file actions and display projections.
    let fileURL: URL
    /// Total bytes occupied by the bundle and its assets.
    let byteCount: Int64

    /// TextBundle filename derived from the canonical URL so it cannot drift from the file action target.
    var filename: String {
        fileURL.lastPathComponent
    }

    init(summary: NoteSummary, markdown: String, location: String, byteCount: Int64) {
        self.init(
            summary: summary,
            statistics: NoteStatistics(markdown: markdown),
            location: location,
            byteCount: byteCount
        )
    }

    /// Creates inspector metadata from independently maintained content statistics.
    init(summary: NoteSummary, statistics: NoteStatistics, location: String, byteCount: Int64) {
        self.statistics = statistics
        createdAt = summary.createdAt
        modifiedAt = summary.modifiedAt
        self.location = location
        fileURL = summary.url
        self.byteCount = byteCount
    }
}
