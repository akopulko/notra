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
    private var requestGeneration = 0
    @ObservationIgnored private var parseTask: Task<Void, Never>?

    var state: State = .idle
    var htmlDocument: MarkdownHTMLDocument?

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

    /// Parses and prepares HTML away from SwiftUI view evaluation.
    func update(
        markdown: String,
        context: MarkdownRenderContext = .empty,
        style: MarkdownStyle = .notra(previewFontName: AppearanceFont.defaultName)
    ) {
        requestGeneration += 1
        let generation = requestGeneration
        let markdownChanged = markdown != parsedMarkdown
        parsedMarkdown = markdown
        let inputBytes = markdown.utf8.count
        let startedAt = Date.now
        parseTask?.cancel()
        parseTask = Task { [parser] in
            let document = if markdownChanged {
                await Task.detached(priority: .userInitiated) {
                    parser(markdown)
                }.value
            } else if case let .parsed(existingDocument) = state {
                existingDocument
            } else {
                parser(markdown)
            }

            var renderer = MarkdownHTMLRenderer(style: style, mode: .preview, context: context)
            let preparedHTML = renderer.render(document)

            let durationMilliseconds = Int(Date.now.timeIntervalSince(startedAt) * 1000)
            AppLog.debug(
                "Parsed markdown preview; bytes=\(inputBytes); blocks=\(document.blocks.count); "
                    + "durationMs=\(durationMilliseconds)"
            )

            guard !Task.isCancelled,
                  generation == requestGeneration,
                  markdown == parsedMarkdown
            else {
                return
            }

            state = .parsed(document)
            htmlDocument = preparedHTML
        }
    }
}
