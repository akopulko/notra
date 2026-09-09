import Foundation

/// Keeps Markdown statistics off the main actor while native text entry remains responsive.
actor NoteStatisticsWorker {
    func statistics(for markdown: String) -> NoteStatistics {
        NoteStatistics(markdown: markdown)
    }
}
