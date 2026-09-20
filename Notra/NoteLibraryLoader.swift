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

    /// Returns the total size of valid TextBundles without scanning root-level support files.
    static func totalByteCount(repository: TextBundleNoteRepository) async throws -> Int64 {
        let loadingTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let summaries = try repository.listNotes()
            var totalByteCount: Int64 = 0
            for summary in summaries {
                try Task.checkCancellation()
                totalByteCount += repository.totalBundleSize(at: summary.url)
            }
            return totalByteCount
        }
        return try await withTaskCancellationHandler {
            try await loadingTask.value
        } onCancel: {
            loadingTask.cancel()
        }
    }
}
