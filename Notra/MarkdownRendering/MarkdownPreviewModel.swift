import Foundation
import Observation

@MainActor
@Observable
final class MarkdownPreviewModel {
    enum State: Equatable {
        case idle
        case parsed(NotraMarkdownDocument)
    }

    private let parser: any MarkdownParsing
    private var parsedMarkdown: String?
    private var parseGeneration = 0
    @ObservationIgnored private var parseTask: Task<Void, Never>?

    var state: State = .idle

    init(parser: any MarkdownParsing = SwiftMarkdownParser()) {
        self.parser = parser
    }

    deinit {
        parseTask?.cancel()
    }

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
                parser.parse(markdown)
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
