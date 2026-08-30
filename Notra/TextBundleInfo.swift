import Foundation

/// Models the JSON metadata required by the TextBundle specification and Notra extensions.
nonisolated struct TextBundleInfo: Codable, Equatable {
    /// Current TextBundle metadata schema version written by Notra.
    static let markdownType = "net.daringfireball.markdown"

    /// TextBundle specification version.
    let version: Int
    /// UTI-like content type identifying Markdown bundles.
    let type: String
    /// Whether the bundle is transient rather than a saved note.
    let transient: Bool
    /// Application identifier recorded as the bundle creator.
    let creatorIdentifier: String
    /// Notra-owned metadata nested under the app's namespaced JSON key.
    let notra: NotraMetadata

    init(
        version: Int = 2,
        type: String = Self.markdownType,
        transient: Bool = false,
        creatorIdentifier: String = "app.notra.Notra",
        notra: NotraMetadata = NotraMetadata()
    ) {
        self.version = version
        self.type = type
        self.transient = transient
        self.creatorIdentifier = creatorIdentifier
        self.notra = notra
    }

    /// Maps the namespaced Notra property to its on-disk JSON key.
    enum CodingKeys: String, CodingKey {
        case version
        case type
        case transient
        case creatorIdentifier
        case notra = "app.notra.Notra"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 2
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? Self.markdownType
        transient = try container.decodeIfPresent(Bool.self, forKey: .transient) ?? false
        creatorIdentifier = try container.decodeIfPresent(String.self, forKey: .creatorIdentifier) ?? "app.notra.Notra"
        notra = try container.decodeIfPresent(NotraMetadata.self, forKey: .notra) ?? NotraMetadata()
    }
}

/// Stores Notra's versioned tag metadata nested inside the TextBundle info document.
nonisolated struct NotraMetadata: Codable, Equatable {
    /// Version for the Notra metadata payload, independent of the outer TextBundle version.
    let version: Int
    /// Normalized tags attached to the note.
    let tags: [NoteTag]

    init(version: Int = 1, tags: [NoteTag] = []) {
        self.version = version
        self.tags = NoteMetadata(tags: tags).tags
    }

    /// Coding keys kept explicit so metadata remains compatible with existing bundles.
    enum CodingKeys: String, CodingKey {
        case version
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        let decodedTags = try container.decodeIfPresent([NoteTag].self, forKey: .tags) ?? []
        tags = NoteMetadata(tags: decodedTags).tags
    }
}
