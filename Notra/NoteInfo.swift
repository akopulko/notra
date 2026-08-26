import Foundation

struct NoteStatistics: Equatable, Sendable {
    static let wordsPerMinute = 200

    let wordCount: Int
    let characterCount: Int
    let lineCount: Int
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

struct NoteInfo: Equatable, Sendable {
    let statistics: NoteStatistics
    let createdAt: Date
    let modifiedAt: Date
    let location: String
    let filename: String
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
