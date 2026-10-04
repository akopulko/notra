import Foundation

/// Derives stable tag choices and applies library-level tag membership.
enum NoteTagFilter {
    nonisolated static func availableTags(in notes: [NoteSummary]) -> [NoteTag] {
        var tagsByID: [String: NoteTag] = [:]
        for note in notes {
            for tag in note.tags {
                if let existing = tagsByID[tag.id] {
                    if tag.name.lexicographicallyPrecedes(existing.name) {
                        tagsByID[tag.id] = tag
                    }
                } else {
                    tagsByID[tag.id] = tag
                }
            }
        }
        return tagsByID.values.sorted {
            let comparison = $0.normalizedKey.localizedStandardCompare($1.normalizedKey)
            return comparison == .orderedSame
                ? $0.normalizedKey.lexicographicallyPrecedes($1.normalizedKey)
                : comparison == .orderedAscending
        }
    }

    nonisolated static func matches(_ note: NoteSummary, selectedIDs: Set<String>) -> Bool {
        selectedIDs.isEmpty || note.tags.contains { selectedIDs.contains($0.id) }
    }

    @MainActor
    static func loadSearchBatch(
        offset: Int,
        limit: Int,
        matchingBundleNames: Set<String>?,
        fetchPage: @MainActor (Int, Int) async -> NoteSearchPage?
    ) async -> NoteTagSearchBatch? {
        guard limit > 0 else { return nil }
        if let matchingBundleNames, matchingBundleNames.isEmpty {
            return NoteTagSearchBatch(resultIDs: [], nextOffset: offset, hasMore: false)
        }

        var nextOffset = offset
        var resultIDs: [URL] = []
        repeat {
            guard !Task.isCancelled else { return nil }
            guard let page = await fetchPage(nextOffset, limit) else { return nil }
            guard !Task.isCancelled else { return nil }
            guard !page.results.isEmpty else {
                return NoteTagSearchBatch(resultIDs: resultIDs, nextOffset: nextOffset, hasMore: false)
            }

            if let matchingBundleNames {
                resultIDs.append(contentsOf: page.results.compactMap { result in
                    matchingBundleNames.contains(result.noteID.lastPathComponent) ? result.noteID : nil
                })
            } else {
                resultIDs.append(contentsOf: page.results.map(\.noteID))
            }
            nextOffset += page.results.count
            if resultIDs.count >= limit || !page.hasMore {
                return NoteTagSearchBatch(resultIDs: resultIDs, nextOffset: nextOffset, hasMore: page.hasMore)
            }
        } while true
    }
}

struct NoteTagSearchBatch {
    let resultIDs: [URL]
    let nextOffset: Int
    let hasMore: Bool
}
