import Foundation

/// Owns one isolated draft workspace and atomically publishes completed captures to the inbox.
nonisolated struct SharedCaptureStore: Sendable {
    nonisolated static let appGroupIdentifierKey = "NotraAppGroupIdentifier"
    nonisolated static let inboxName = "ShareInbox"

    nonisolated let rootURL: URL

    #if os(iOS)
    nonisolated static func production() throws -> SharedCaptureStore {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: appGroupIdentifierKey) as? String,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        else {
            throw NoteRepositoryError.storageUnavailable
        }
        let inboxURL = groupURL.appendingPathComponent(inboxName, isDirectory: true)
        try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        return SharedCaptureStore(rootURL: inboxURL)
    }
    #endif

    nonisolated func createDraftDirectory() throws -> URL {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let directory = rootURL.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    nonisolated func publish(draftDirectory: URL, noteURL: URL) throws -> UUID {
        let captureID = UUID(uuidString: noteURL.deletingPathExtension().lastPathComponent)
        guard let captureID,
              draftDirectory.deletingLastPathComponent().standardizedFileURL == rootURL.standardizedFileURL,
              draftDirectory.lastPathComponent.hasPrefix(".staging-"),
              noteURL.deletingLastPathComponent().standardizedFileURL == draftDirectory.standardizedFileURL,
              noteURL.pathExtension == TextBundleNoteRepository.bundleExtension
        else {
            throw NoteRepositoryError.invalidBundle(noteURL)
        }
        let infoURL = noteURL.appendingPathComponent(TextBundleNoteRepository.infoFilename)
        let textURL = noteURL.appendingPathComponent(TextBundleNoteRepository.textFilename)
        guard FileManager.default.fileExists(atPath: infoURL.path(percentEncoded: false)),
              FileManager.default.fileExists(atPath: textURL.path(percentEncoded: false))
        else {
            throw NoteRepositoryError.invalidBundle(noteURL)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let infoData = try encoder.encode(TextBundleInfo(notra: NotraMetadata(shareCaptureID: captureID)))
        try infoData.write(to: infoURL, options: .atomic)
        let destination = rootURL.appendingPathComponent(captureID.uuidString, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.moveItem(at: draftDirectory, to: destination)
        return captureID
    }

    nonisolated func discard(draftDirectory: URL) throws {
        guard draftDirectory.deletingLastPathComponent().standardizedFileURL == rootURL.standardizedFileURL,
              draftDirectory.lastPathComponent.hasPrefix(".staging-")
        else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        if FileManager.default.fileExists(atPath: draftDirectory.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: draftDirectory)
        }
    }
}
