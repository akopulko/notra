import Foundation
import Observation

/// Parses preview text off the view update path and rejects stale asynchronous results.
@MainActor
@Observable
final class MarkdownPreviewModel {
    enum State: Equatable {
        case idle
        case parsed(NotraMarkdownDocument)
    }

    /// Latest input accepted by the model; newer generations invalidate older parse tasks.
    private let parser: @Sendable (String) -> NotraMarkdownDocument
    private var parsedMarkdown: String?
    private var parseGeneration = 0
    @ObservationIgnored private var parseTask: Task<Void, Never>?

    var state: State = .idle

    init(
        parser: @escaping @Sendable (String) -> NotraMarkdownDocument = { markdown in
            SwiftMarkdownParser().parse(markdown)
        }
    ) {
        self.parser = parser
    }

    deinit {
        parseTask?.cancel()
    }

    /// Starts a detached parse and publishes it only if no newer text superseded the request.
    func update(markdown: String) {
        guard markdown != parsedMarkdown else {
            return
        }

        parsedMarkdown = markdown
        parseGeneration += 1
        let generation = parseGeneration
        let inputBytes = markdown.utf8.count
        let startedAt = Date.now
        parseTask?.cancel()
        parseTask = Task { [parser] in
            let document = await Task.detached(priority: .userInitiated) {
                parser(markdown)
            }.value

            let durationMilliseconds = Int(Date.now.timeIntervalSince(startedAt) * 1000)
            AppLog.debug(
                "Parsed markdown preview; bytes=\(inputBytes); blocks=\(document.blocks.count); "
                    + "rows=\(document.renderRows.count); durationMs=\(durationMilliseconds)"
            )

            guard !Task.isCancelled,
                  generation == parseGeneration,
                  markdown == parsedMarkdown
            else {
                return
            }

            state = .parsed(document)
        }
    }
}
