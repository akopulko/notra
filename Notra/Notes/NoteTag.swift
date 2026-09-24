import Foundation

/// A validated, normalized tag value used in note metadata and search queries.
nonisolated struct NoteTag: Equatable, Hashable, Identifiable, Sendable, Codable {
    /// User-entered spelling retained for display and serialization.
    let name: String

    /// Stable identity that ignores case and diacritics for SwiftUI and duplicate checks.
    var id: String {
        normalizedKey
    }

    /// Display label without the Markdown hashtag prefix.
    var displayName: String {
        name
    }

    /// Display label formatted for the editor's hashtag syntax.
    var prefixedDisplayName: String {
        "#\(name)"
    }

    /// Comparison key shared by metadata normalization, selection, and search indexing.
    var normalizedKey: String {
        Self.normalizedKey(for: name)
    }

    /// Trims and validates input, rejecting punctuation and empty tags.
    init?(_ rawValue: String) {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidName(trimmedValue) else {
            return nil
        }
        name = trimmedValue
    }

    /// Accepts the optional hashtag prefix used when people enter tags directly in the inspector.
    init?(inspectorInput rawValue: String) {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagName = trimmedValue.first == "#" ? String(trimmedValue.dropFirst()) : trimmedValue
        self.init(tagName)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let tag = NoteTag(rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid note tag"
            )
        }
        name = tag.name
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }

    /// Folds case and diacritics so visually equivalent tags compare as one value.
    static func normalizedKey(for value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    /// Accepts only letters, numbers, hyphens, and underscores in a tag name.
    static func isValidName(_ value: String) -> Bool {
        guard !value.isEmpty else {
            return false
        }

        return value.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
        }
    }

    /// Appends a tag only when its normalized key is not already present.
    static func appending(_ tag: NoteTag, to tags: [NoteTag]) -> (tags: [NoteTag], inserted: Bool) {
        guard !tags.contains(where: { $0.normalizedKey == tag.normalizedKey }) else {
            return (tags, false)
        }
        return (tags + [tag], true)
    }
}

/// Note-owned metadata kept separate from the Markdown document body.
nonisolated struct NoteMetadata: Equatable, Sendable {
    /// Tags in first-seen order after duplicate normalization.
    var tags: [NoteTag]
    /// Timestamp used to persist pin state and ordering with the TextBundle.
    var pinnedAt: Date?

    init(tags: [NoteTag] = [], pinnedAt: Date? = nil) {
        self.tags = Self.unique(tags)
        self.pinnedAt = pinnedAt
    }

    /// Adds a tag and reports whether it changed the metadata.
    mutating func add(_ tag: NoteTag) -> Bool {
        let result = NoteTag.appending(tag, to: tags)
        tags = result.tags
        return result.inserted
    }

    /// Removes every spelling of a tag with the same normalized key.
    mutating func remove(_ tag: NoteTag) {
        tags.removeAll { $0.normalizedKey == tag.normalizedKey }
    }

    private static func unique(_ tags: [NoteTag]) -> [NoteTag] {
        var seenKeys: Set<String> = []
        return tags.filter { tag in
            seenKeys.insert(tag.normalizedKey).inserted
        }
    }
}

/// Result used by the editor to distinguish a new tag from a duplicate.
nonisolated enum NoteTagMutationResult: Equatable, Sendable {
    case added(NoteTag)
    case duplicate(NoteTag)
}
