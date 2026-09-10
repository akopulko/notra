import Markdown

/// Immutable facts extracted while walking one Markdown AST.
struct MarkdownDocumentAnalysis: Equatable, Sendable {
    let hasChecklist: Bool
    let attachmentSources: [String]

    /// Performs one traversal for the checklist and attachment projections.
    nonisolated static func analyse(markdown: String) -> Self {
        let document = Document(parsing: markdown)
        var hasChecklist = false
        var attachmentSources: [String] = []

        func visit(_ markup: any Markup) {
            if let listItem = markup as? ListItem, listItem.checkbox != nil {
                hasChecklist = true
            }

            if let image = markup as? Markdown.Image, let source = image.source {
                attachmentSources.append(source)
            } else if let link = markup as? Markdown.Link, let destination = link.destination {
                attachmentSources.append(destination)
            }

            for child in markup.children {
                visit(child)
            }
        }

        visit(document)
        return Self(hasChecklist: hasChecklist, attachmentSources: attachmentSources)
    }
}
