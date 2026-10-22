import Foundation

/// Serially files completed captures into the currently selected durable library.
actor SharedCaptureImporter {
    static let shared = SharedCaptureImporter()
    struct Result: Sendable {
        var notes: [Note] = []
        var errors: [String] = []
    }

    private struct ImportJournal: Codable {
        let destinationStorageLocation: String
        let destinationRootURL: String
    }

    private let inboxURL: URL?
    private let destination: TextBundleNoteRepository?

    init(inboxURL: URL? = nil, destination: TextBundleNoteRepository? = nil) {
        self.inboxURL = inboxURL
        self.destination = destination
    }

    func drain(
        inboxURL requestedInboxURL: URL? = nil,
        destination requestedDestination: TextBundleNoteRepository? = nil
    ) async -> Result {
        guard let inboxURL = requestedInboxURL ?? inboxURL,
              let destination = requestedDestination ?? destination
        else {
            return Result(errors: [NoteRepositoryError.storageUnavailable.localizedDescription])
        }
        var result = Result()
        let fileManager = FileManager.default
        var attempted = Set<UUID>()
        while let entries = try? fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            let pendingEntries = entries
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .filter { entry in
                    guard let captureID = UUID(uuidString: entry.lastPathComponent) else { return false }
                    return !attempted.contains(captureID)
                }
            guard !pendingEntries.isEmpty else { break }
            for entry in pendingEntries {
                guard let captureID = UUID(uuidString: entry.lastPathComponent) else { continue }
                attempted.insert(captureID)
                do {
                    let note = try fileCapture(captureID, at: entry, destination: destination)
                    result.notes.append(note)
                    try fileManager.removeItem(at: entry)
                } catch {
                    AppLog.error("Failed to file shared capture \(captureID): \(error.localizedDescription)")
                    result.errors.append(error.localizedDescription)
                }
            }
        }
        return result
    }

    private func fileCapture(
        _ captureID: UUID,
        at captureDirectory: URL,
        destination: TextBundleNoteRepository
    ) throws -> Note {
        let fileManager = FileManager.default
        let canonicalRoot = destination.rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let location = destination.storageLocation.rawValue
        let journalURL = captureDirectory.appendingPathComponent("import.json")
        let journal = ImportJournal(
            destinationStorageLocation: location,
            destinationRootURL: canonicalRoot.absoluteString
        )
        if fileManager.fileExists(atPath: journalURL.path(percentEncoded: false)) {
            let recorded = try JSONDecoder().decode(ImportJournal.self, from: Data(contentsOf: journalURL))
            guard recorded.destinationStorageLocation == location,
                  URL(string: recorded.destinationRootURL)?.standardizedFileURL.resolvingSymlinksInPath() == canonicalRoot
            else {
                throw NoteRepositoryError.storageUnavailable
            }
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(journal).write(to: journalURL, options: .atomic)
        }

        let sourceURL = captureDirectory
            .appendingPathComponent("\(captureID.uuidString).textbundle", isDirectory: true)
        let source = try TextBundleNoteRepository(rootURL: captureDirectory).loadNote(at: sourceURL)
        guard source.metadata.shareCaptureID == captureID else {
            throw NoteRepositoryError.invalidBundle(sourceURL)
        }

        let finalURL = canonicalRoot.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)
        if fileManager.fileExists(atPath: finalURL.path(percentEncoded: false)) {
            let existing = try destination.loadNote(at: finalURL)
            guard existing.metadata.shareCaptureID == captureID else {
                throw NoteRepositoryError.invalidBundle(finalURL)
            }
            return existing
        }

        let stagingDirectory = canonicalRoot.appendingPathComponent(
            ".share-import-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
        let stagedBundle = stagingDirectory.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)
        do {
            try fileManager.copyItem(at: sourceURL, to: stagedBundle)
            try preserveDates(from: sourceURL, to: stagedBundle)
            let stagedNote = try destination.loadNote(at: stagedBundle)
            guard stagedNote.metadata.shareCaptureID == captureID else {
                throw NoteRepositoryError.invalidBundle(stagedBundle)
            }
            try coordinatePublication(stagedBundle, to: finalURL)
            let publishedNote = try destination.loadNote(at: finalURL)
            guard publishedNote.metadata.shareCaptureID == captureID else {
                throw NoteRepositoryError.invalidBundle(finalURL)
            }
            try fileManager.removeItem(at: stagingDirectory)
            return publishedNote
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            throw error
        }
    }

    private func preserveDates(from sourceURL: URL, to destinationURL: URL) throws {
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey]
        let bundleDates = try sourceURL.resourceValues(forKeys: keys)
        let textDates = try sourceURL.appendingPathComponent(TextBundleNoteRepository.textFilename)
            .resourceValues(forKeys: keys)
        var copiedBundleURL = destinationURL
        var copiedTextURL = destinationURL.appendingPathComponent(TextBundleNoteRepository.textFilename)
        try copiedBundleURL.setResourceValues(bundleDates)
        try copiedTextURL.setResourceValues(textDates)
    }

    private func coordinatePublication(_ stagedBundle: URL, to finalURL: URL) throws {
        var coordinationError: NSError?
        var publicationError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: finalURL,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try FileManager.default.moveItem(at: stagedBundle, to: coordinatedURL)
            } catch {
                publicationError = error
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        if let publicationError {
            throw publicationError
        }
    }
}
