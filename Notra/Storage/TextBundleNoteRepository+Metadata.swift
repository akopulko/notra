import Foundation

extension TextBundleNoteRepository {
    /// Reads Notra metadata, treating missing metadata as an unpinned note without tags.
    nonisolated func noteMetadata(at noteURL: URL) throws -> NoteMetadata {
        let infoURL = noteURL.appendingPathComponent(Self.infoFilename)
        guard FileManager.default.fileExists(atPath: infoURL.path(percentEncoded: false)) else {
            return NoteMetadata()
        }

        let data = try Data(contentsOf: infoURL)
        let info = try JSONDecoder().decode(NotraMetadataEnvelope.self, from: data)
        return NoteMetadata(tags: info.notra.tags, pinnedAt: info.notra.pinnedAt)
    }

    /// Keeps damaged notes discoverable while recording why their metadata could not be read.
    nonisolated func summaryMetadata(at noteURL: URL) -> NoteMetadata {
        do {
            return try noteMetadata(at: noteURL)
        } catch {
            AppLog.error("Failed to read note metadata: \(String(describing: error))")
            return NoteMetadata()
        }
    }

    /// Merges normalized Notra metadata into existing JSON so unknown keys survive updates.
    func updateNoteMetadata(_ metadata: NoteMetadata, for noteURL: URL) throws {
        guard FileManager.default.fileExists(atPath: noteURL.path(percentEncoded: false)) else {
            throw NoteRepositoryError.noteNotFound
        }

        let infoURL = noteURL.appendingPathComponent(Self.infoFilename)
        var root = try metadataJSONObject(at: infoURL)
        // Refuse to overwrite unreadable Notra metadata with an empty in-memory fallback.
        _ = try noteMetadata(at: noteURL)
        var appMetadata = root[Self.appMetadataKey] as? [String: Any] ?? [:]

        appMetadata["version"] = appMetadata["version"] ?? 1
        appMetadata["tags"] = metadata.tags.map(\.name)
        if let pinnedAt = metadata.pinnedAt {
            appMetadata["pinnedAt"] = pinnedAt.timeIntervalSinceReferenceDate
        } else {
            appMetadata.removeValue(forKey: "pinnedAt")
        }
        root[Self.appMetadataKey] = appMetadata
        root["version"] = root["version"] ?? 2
        root["type"] = root["type"] ?? TextBundleInfo.markdownType
        root["creatorIdentifier"] = root["creatorIdentifier"] ?? Self.appMetadataKey

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: infoURL, options: .atomic)
    }

    /// Decodes existing metadata as a dictionary to preserve fields Notra does not own.
    private func metadataJSONObject(at infoURL: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: infoURL.path(percentEncoded: false)) else {
            return [:]
        }

        let data = try Data(contentsOf: infoURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NoteRepositoryError.invalidMetadata
        }
        return object
    }
}
