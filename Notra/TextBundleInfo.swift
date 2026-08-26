import Foundation

nonisolated struct TextBundleInfo: Codable, Equatable {
    static let markdownType = "net.daringfireball.markdown"

    let version: Int
    let type: String
    let transient: Bool
    let creatorIdentifier: String
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

nonisolated struct NotraMetadata: Codable, Equatable {
    let version: Int
    let tags: [NoteTag]

    init(version: Int = 1, tags: [NoteTag] = []) {
        self.version = version
        self.tags = NoteMetadata(tags: tags).tags
    }

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
