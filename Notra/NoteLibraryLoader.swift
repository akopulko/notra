import Foundation

/// Loads and sorts full TextBundle libraries without occupying the main actor.
nonisolated enum NoteLibraryLoader {
    /// Returns sorted sidebar summaries while forwarding cancellation to the disk-bound task.
    static func load(
        repository: TextBundleNoteRepository,
        sortPreference: NoteSortPreference
    ) async throws -> [NoteSummary] {
        try await runDetached {
            try Task.checkCancellation()
            let summaries = try repository.listNotes()
            try Task.checkCancellation()
            return sortPreference.sorted(summaries)
        }
    }

    /// Returns the total size of valid TextBundles without scanning root-level support files.
    static func totalByteCount(repository: TextBundleNoteRepository) async throws -> Int64 {
        try await runDetached {
            try Task.checkCancellation()
            let summaries = try repository.listNotes()
            var totalByteCount: Int64 = 0
            for summary in summaries {
                try Task.checkCancellation()
                totalByteCount += repository.totalBundleSize(at: summary.url)
            }
            return totalByteCount
        }
    }

    private static func runDetached<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let task = Task.detached(priority: .userInitiated, operation: operation)
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
