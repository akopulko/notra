import Foundation

/// Loads and sorts full TextBundle libraries without occupying the main actor.
nonisolated enum NoteLibraryLoader {
    /// Returns sorted sidebar summaries while forwarding cancellation to the disk-bound task.
    static func load(
        repository: TextBundleNoteRepository,
        sortPreference: NoteSortPreference
    ) async throws -> [NoteSummary] {
        let loadingTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let summaries = try repository.listNotes()
            try Task.checkCancellation()
            return sortPreference.sorted(summaries)
        }
        return try await withTaskCancellationHandler {
            try await loadingTask.value
        } onCancel: {
            loadingTask.cancel()
        }
    }
}
