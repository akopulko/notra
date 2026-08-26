import Foundation

nonisolated struct NoteTag: Equatable, Hashable, Identifiable, Sendable, Codable {
    let name: String

    var id: String {
        normalizedKey
    }

    var displayName: String {
        name
    }

    var prefixedDisplayName: String {
        "#\(name)"
    }

    var normalizedKey: String {
        Self.normalizedKey(for: name)
    }

    init?(_ rawValue: String) {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidName(trimmedValue) else {
            return nil
        }
        name = trimmedValue
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

    static func normalizedKey(for value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    static func isValidName(_ value: String) -> Bool {
        guard !value.isEmpty else {
            return false
        }

        return value.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
        }
    }

    static func appending(_ tag: NoteTag, to tags: [NoteTag]) -> (tags: [NoteTag], inserted: Bool) {
        guard !tags.contains(where: { $0.normalizedKey == tag.normalizedKey }) else {
            return (tags, false)
        }
        return (tags + [tag], true)
    }
}

nonisolated struct NoteMetadata: Equatable, Sendable {
    var tags: [NoteTag]

    init(tags: [NoteTag] = []) {
        self.tags = Self.unique(tags)
    }

    mutating func add(_ tag: NoteTag) -> Bool {
        let result = NoteTag.appending(tag, to: tags)
        tags = result.tags
        return result.inserted
    }

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

nonisolated enum NoteTagMutationResult: Equatable, Sendable {
    case added(NoteTag)
    case duplicate(NoteTag)
}
