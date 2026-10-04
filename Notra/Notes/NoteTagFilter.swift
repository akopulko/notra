import Foundation

/// Derives stable tag choices and applies library-level tag membership.
enum NoteTagFilter {
    private struct TagUsage {
        var tag: NoteTag
        var count: Int
    }

    nonisolated static func availableTags(in notes: [NoteSummary]) -> [NoteTag] {
        var tagsByID: [String: TagUsage] = [:]
        var seenIDsInNote: Set<String> = []
        for note in notes {
            seenIDsInNote.removeAll(keepingCapacity: true)
            for tag in note.tags {
                let tagID = tag.id
                if var usage = tagsByID[tagID] {
                    if tag.name.lexicographicallyPrecedes(usage.tag.name) {
                        usage.tag = tag
                    }
                    if seenIDsInNote.insert(tagID).inserted {
                        usage.count += 1
                    }
                    tagsByID[tagID] = usage
                } else {
                    tagsByID[tagID] = TagUsage(tag: tag, count: 1)
                    seenIDsInNote.insert(tagID)
                }
            }
        }
        return tagsByID.values.sorted {
            guard $0.count == $1.count else { return $0.count > $1.count }
            let comparison = $0.tag.normalizedKey.localizedStandardCompare($1.tag.normalizedKey)
            return comparison == .orderedSame
                ? $0.tag.normalizedKey.lexicographicallyPrecedes($1.tag.normalizedKey)
                : comparison == .orderedAscending
        }.map(\.tag)
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
