import Foundation
@testable import Notra
import SwiftUI
import Testing

@MainActor
/// Checks parsing, styling, and native Markdown rendering inputs used by preview and PDF export.
struct MarkdownRenderingTests {
    @Test func webThemeKeepsNormalTextSeparateFromCodeText() {
        let webTheme = MarkdownWebTheme(theme: .dark)

        #expect(webTheme.bodyText == MarkdownTheme.dark.preview.body.hex)
        #expect(webTheme.codeBlockText == MarkdownTheme.dark.code.plain.hex)
        #expect(webTheme.inlineCodeText == MarkdownTheme.dark.preview.inlineCode.hex)
        #expect(webTheme.headingPrimary == MarkdownTheme.dark.preview.headingPrimary.hex)
        #expect(webTheme.codeColour(for: .keyword) == MarkdownTheme.dark.code.keyword.hex)
    }

    @Test func webThemePreservesSystemFallbacksWhenPreviewThemingIsDisabled() {
        let webTheme = MarkdownWebTheme(theme: nil)

        #expect(webTheme.bodyText == "CanvasText")
        #expect(webTheme.headingPrimary == "CanvasText")
        #expect(webTheme.linkText == "LinkText")
        #expect(webTheme.inlineCodeText == "CanvasText")
        #expect(webTheme.codeColour(for: .keyword) == "CanvasText")
    }

    @Test func htmlRendererAppliesPreviewAndCodeSemanticColours() {
        let document = SwiftMarkdownParser().parse("""
        # Heading

        **Bold** *Italic* ~~Removed~~ [Link](https://example.com) `inline`

        - List item

        > Quote

        ```swift
        let enabled = true
        ```
        """)
        var renderer = MarkdownHTMLRenderer(
            style: .notra(previewFontName: AppearanceFont.defaultName, theme: .dark),
            mode: .preview,
            context: .empty
        )

        let html = renderer.render(document).html

        #expect(html.contains("body { box-sizing: border-box; padding: 24px; color: #c0caf5; }"))
        #expect(html.contains("h1, h2 { color: #7aa2f7;"))
        #expect(html.contains("strong { color: #e0af68; }"))
        #expect(html.contains("em { color: #bb9af7; }"))
        #expect(html.contains("del { color: #9aa5ce; }"))
        #expect(html.contains("li::marker { color: #f7768e; }"))
        #expect(html.contains("blockquote { border-left: 4px solid #565f89; color: #9ece6a;"))
        #expect(html.contains("<code class=\"inline-code\">inline</code>"))
        #expect(html.contains("class=\"code-constant\" style=\"color:#f7768e\">true</span>"))
    }

    @Test func htmlRendererPreservesInlineImageOrder() throws {
        let document = SwiftMarkdownParser().parse("Before ![Image](https://example.com/image.png) After")
        var renderer = MarkdownHTMLRenderer(
            style: .notra(previewFontName: AppearanceFont.defaultName),
            mode: .pdf,
            context: .empty
        )

        let html = renderer.render(document).html
        let beforeIndex = try #require(html.range(of: "Before ")?.lowerBound)
        let imageIndex = try #require(html.range(of: "<img class=\"markdown-image\"")?.lowerBound)
        let afterIndex = try #require(html.range(of: " After")?.lowerBound)

        #expect(beforeIndex < imageIndex)
        #expect(imageIndex < afterIndex)
    }

    @Test func checkedTaskCheckboxesUseThePreviewItalicColour() {
        let document = SwiftMarkdownParser().parse("- [x] Done")
        var darkRenderer = MarkdownHTMLRenderer(
            style: .notra(previewFontName: AppearanceFont.defaultName, theme: .dark),
            mode: .preview,
            context: .empty
        )
        var lightRenderer = MarkdownHTMLRenderer(
            style: .notra(previewFontName: AppearanceFont.defaultName, theme: .light),
            mode: .preview,
            context: .empty
        )
        var pdfRenderer = MarkdownHTMLRenderer(
            style: .notra(previewFontName: AppearanceFont.defaultName, renderMode: .pdf),
            mode: .pdf,
            context: .empty
        )

        let darkHTML = darkRenderer.render(document).html
        let lightHTML = lightRenderer.render(document).html
        let pdfHTML = pdfRenderer.render(document).html

        #expect(darkHTML.contains("accent-color: \(MarkdownTheme.dark.preview.italic.hex)"))
        #expect(lightHTML.contains("accent-color: \(MarkdownTheme.light.preview.italic.hex)"))
        #expect(!pdfHTML.contains("accent-color:"))
    }

    @Test func previewConstrainsWideContentWithoutChangingPDFLayout() {
        let longToken = String(repeating: "unbroken", count: 64)
        let document = SwiftMarkdownParser().parse("Preview `\(longToken)`")
        let style = MarkdownStyle.notra(previewFontName: AppearanceFont.defaultName)
        var previewRenderer = MarkdownHTMLRenderer(style: style, mode: .preview, context: .empty)
        var pdfRenderer = MarkdownHTMLRenderer(style: style, mode: .pdf, context: .empty)

        let viewport = "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
        let constrainedRoot = "html, body { width: 100%; max-width: 100%; overflow-x: hidden; }"
        let constrainedTable = "table { width: 100%; max-width: 100%; table-layout: fixed; }"
        let localCodeOverflow = "pre, pre code { overflow-wrap: normal; }"
        let previewHTML = previewRenderer.render(document).html
        let pdfHTML = pdfRenderer.render(document).html

        #expect(previewHTML.contains(viewport))
        #expect(previewHTML.contains(constrainedRoot))
        #expect(previewHTML.contains("body { overflow-wrap: anywhere; }"))
        #expect(previewHTML.contains(constrainedTable))
        #expect(previewHTML.contains(localCodeOverflow))
        #expect(!pdfHTML.contains(viewport))
        #expect(!pdfHTML.contains(constrainedRoot))
    }

    @Test func previewCodeSyntaxThemeFollowsThePreviewThemeOption() {
        let themedPreview = MarkdownStyle.notra(
            previewFontName: AppearanceFont.defaultName,
            theme: .dark
        )
        let defaultPreview = MarkdownStyle.notra(previewFontName: AppearanceFont.defaultName)
        let themedPDF = MarkdownStyle.notra(
            previewFontName: AppearanceFont.defaultName,
            theme: .dark,
            renderMode: .pdf
        )

        #expect(themedPreview.codeSyntaxTheme == .dark)
        #expect(defaultPreview.codeSyntaxTheme == nil)
        #expect(themedPDF.codeSyntaxTheme == nil)
    }

    @Test func pdfHTMLUsesAThemeIndependentLightA4Layout() {
        let document = SwiftMarkdownParser().parse("# Heading\n\n```swift\nlet value = 42\n```")
        var renderer = MarkdownHTMLRenderer(
            style: .notra(
                previewFontName: AppearanceFont.defaultName,
                theme: .dark,
                renderMode: .pdf
            ),
            mode: .pdf,
            context: .empty
        )

        let html = renderer.render(document).html

        #expect(html.contains(":root { color-scheme: only light; }"))
        #expect(html.contains("body { box-sizing: border-box; padding: 24px; color: #111111; }"))
        #expect(html.contains("<main class=\"pdf-content\">"))
        #expect(html.contains("width: 595px; height: 842px"))
        #expect(html.contains("column-width: 499px; column-gap: 96px"))
        #expect(html.contains("break-inside: avoid-column"))
        #expect(!html.contains(MarkdownTheme.dark.preview.body.hex))
        #expect(!html.contains(MarkdownTheme.dark.code.keyword.hex))
    }

    @Test func pdfHTMLIncludesRemoteImages() {
        let document = SwiftMarkdownParser().parse("![Remote](https://example.com/test-image.jpg)")
        var renderer = MarkdownHTMLRenderer(
            style: .notra(previewFontName: AppearanceFont.defaultName, renderMode: .pdf),
            mode: .pdf,
            context: .empty
        )

        let html = renderer.render(document).html

        #expect(html.contains("src=\"https://example.com/test-image.jpg\""))
        #expect(html.contains("<span class=\"pdf-image-container\"><img"))
    }

    @Test
    func `parses representative markdown surface`() {
        let document = SwiftMarkdownParser().parse("""
        # Heading

        Paragraph with **bold**, *italic*, `code`, and [link](https://example.com).

        - Item one
        - Item two
          - Nested item

        1. First
        2. Second

        > Blockquote

        ```swift
        let value = 42
        ```

        - [ ] Todo
        - [x] Done

        ---

        | Name | Value |
        |------|-------|
        | Foo  | Bar   |
        """)

        #expect(document.blocks.contains { block in
            if case .heading(_, 1, _) = block {
                return true
            }
            return false
        })
        #expect(document.blocks.contains { block in
            if case let .codeBlock(_, "swift", code) = block {
                return code.trimmingCharacters(in: .newlines) == "let value = 42"
            }
            return false
        })
        #expect(document.blocks.contains { block in
            if case let .table(_, table) = block {
                return table.header.count == 2 && table.rows.count == 1
            }
            return false
        })
    }

    @Test
    func `parses image source and alt text`() {
        let document = SwiftMarkdownParser().parse("![Example](assets/example.jpg)")

        guard case let .paragraph(_, inlines) = document.blocks.first,
              case let .image(source, _, alt) = inlines.first
        else {
            Issue.record("Expected an image paragraph")
            return
        }

        #expect(source == "assets/example.jpg")
        #expect(alt == "Example")
    }

    @Test
    func `resolves spec asset reference inside text bundle assets`() throws {
        let noteURL = URL(fileURLWithPath: "/tmp/example.textbundle", isDirectory: true)
        let context = MarkdownRenderContext.textBundle(noteURL: noteURL)
        let resolved = try #require(
            MarkdownAttachmentReferences.resolve("assets/example.jpg", assetBaseURL: context.assetBaseURL)
        )

        #expect(resolved == noteURL.appendingPathComponent("assets/example.jpg"))
    }

    @Test
    func `rejects image references outside text bundle assets`() {
        let noteURL = URL(fileURLWithPath: "/tmp/example.textbundle", isDirectory: true)
        let context = MarkdownRenderContext.textBundle(noteURL: noteURL)

        #expect(MarkdownAttachmentReferences.resolve("../outside.jpg", assetBaseURL: context.assetBaseURL) == nil)
        #expect(MarkdownAttachmentReferences.resolve("assets/../outside.jpg", assetBaseURL: context.assetBaseURL) == nil)
        #expect(MarkdownAttachmentReferences.resolve("assets/%2e%2e/outside.jpg", assetBaseURL: context.assetBaseURL) == nil)
    }

    @Test
    func `parses GFM table alignment and cell normalization`() {
        let document = SwiftMarkdownParser().parse("""
        | Left | Center | Right |
        | :--- | :----: | ----: |
        | A \\| pipe | `B | C` | D |
        | One | Two |
        | X | Y | Z | Extra |
        """)

        guard let table = firstTable(in: document) else {
            Issue.record("Expected table")
            return
        }

        #expect(table.columnAlignments == [.leading, .center, .trailing])
        #expect(table.header.map { plainText(in: $0.inlines) } == ["Left", "Center", "Right"])
        #expect(table.rows.count == 3)
        #expect(table.rows.allSatisfy { $0.cells.count == 3 })
        #expect(plainText(in: table.rows[0].cells[0].inlines) == "A | pipe")
        #expect(plainText(in: table.rows[0].cells[1].inlines) == "B | C")
        #expect(plainText(in: table.rows[1].cells[2].inlines).isEmpty)
        #expect(plainText(in: table.rows[2].cells[2].inlines) == "Z")
    }

    @Test
    func `parses invalid table as paragraph`() {
        let document = SwiftMarkdownParser().parse("""
        | Left | Right |
        | --- |
        | One | Two |
        """)

        #expect(!document.blocks.contains { block in
            if case .table = block {
                return true
            }
            return false
        })
    }

    @Test
    func `parses task list states`() {
        let document = SwiftMarkdownParser().parse("""
        - [ ] Todo
        - [x] Done
        """)

        guard case let .unorderedList(_, items) = document.blocks.first else {
            Issue.record("Expected unordered list")
            return
        }

        #expect(items.map(\.taskState) == [.unchecked, .checked])
    }

    @Test
    func `renders task text beside its checkbox without a list marker`() {
        let document = SwiftMarkdownParser().parse("""
        - [ ] test 1
        - [x] test 2
        """)
        var renderer = MarkdownHTMLRenderer(
            style: .notra(previewFontName: AppearanceFont.defaultName),
            mode: .preview,
            context: .empty
        )

        let html = renderer.render(document).html

        #expect(html.contains("<li class=\"task-item\"><input class=\"task-checkbox\" type=\"checkbox\" disabled><span>test 1</span></li>"))
        #expect(html.contains("<li class=\"task-item\"><input class=\"task-checkbox\" type=\"checkbox\" checked disabled><span>test 2</span></li>"))
        #expect(!html.contains("<li><input type=\"checkbox\""))
    }

    @Test
    func `formatted bare list item parses as an unchecked task with its paragraph text`() {
        let text = "- Item"
        let formatted = MarkdownFormatting.applyTodoResult(
            to: text,
            selection: text.startIndex ..< text.endIndex
        ).text
        let document = SwiftMarkdownParser().parse(formatted)

        guard case let .unorderedList(_, items) = document.blocks.first,
              let item = items.first,
              case let .paragraph(_, inlines) = item.blocks.first
        else {
            Issue.record("Expected one unchecked task item")
            return
        }

        #expect(item.taskState == .unchecked)
        #expect(plainText(in: inlines) == "Item")
    }

    @Test
    func `compacts a paragraph directly followed by a list`() {
        let document = SwiftMarkdownParser().parse("""
        User can:
        - Create a trip
        - Archive a trip
        """)

        #expect(document.renderRows.first?.usesCompactParagraphSpacing == true)
    }

    @Test
    func `preserves paragraph spacing before a list separated by a blank line`() {
        let document = SwiftMarkdownParser().parse("""
        User can:

        - Create a trip
        - Archive a trip
        """)

        #expect(document.renderRows.first?.usesCompactParagraphSpacing == false)
    }

    @Test
    func `compacts a paragraph directly followed by an ordered list`() {
        let document = SwiftMarkdownParser().parse("""
        Steps:
        1. Create a trip
        2. Archive a trip
        """)

        #expect(document.renderRows.first?.usesCompactParagraphSpacing == true)
    }

    @Test
    func `preserves spacing after an unordered list followed by a blank line`() {
        let document = SwiftMarkdownParser().parse("""
        - First
        - Second

        After the list
        """)

        #expect(document.renderRows.map(\.usesListTrailingParagraphSpacing) == [false, true, false])
    }

    @Test
    func `preserves spacing after an ordered list followed by a blank line`() {
        let document = SwiftMarkdownParser().parse("""
        1. First
        2. Second

        After the list
        """)

        #expect(document.renderRows.map(\.usesListTrailingParagraphSpacing) == [false, true, false])
    }

    @Test
    func `preserves compact paragraph spacing in documents with tables`() {
        let document = SwiftMarkdownParser().parse("""
        User can:
        - Create a trip

        | Status |
        | --- |
        | Active |
        """)

        #expect(document.renderRows.first?.usesCompactParagraphSpacing == true)
    }

    @Test
    func `preserves list spacing in documents with tables`() {
        let document = SwiftMarkdownParser().parse("""
        - First

        After the list

        | Status |
        | --- |
        | Active |
        """)

        #expect(document.renderRows.map(\.usesListTrailingParagraphSpacing) == [true, false, false])
    }

    @Test
    func `parses raw HTML as literal text`() {
        let document = SwiftMarkdownParser().parse("""
        <section>
        <strong>Literal only</strong>
        </section>

        Text with <em>inline HTML</em>.
        """)

        #expect(document.blocks.contains { block in
            guard case let .paragraph(_, inlines) = block else {
                return false
            }
            return plainText(in: inlines).contains("<section>")
        })
        #expect(document.blocks.contains { block in
            guard case let .paragraph(_, inlines) = block else {
                return false
            }
            return plainText(in: inlines) == "Text with <em>inline HTML</em>."
        })
    }

    @Test
    func `parses GFM autolinks`() {
        let document = SwiftMarkdownParser().parse("""
        Visit www.commonmark.org/help.

        Open http://commonmark.org and contact foo@bar.baz.

        Use mailto:person@example.com or xmpp:person@example.com/chat.
        """)

        let links = document.blocks.flatMap(links(in:))

        #expect(links.contains(.init(destination: "http://www.commonmark.org/help", label: "www.commonmark.org/help")))
        #expect(links.contains(.init(destination: "http://commonmark.org", label: "http://commonmark.org")))
        #expect(links.contains(.init(destination: "mailto:foo@bar.baz", label: "foo@bar.baz")))
        #expect(links.contains(.init(destination: "mailto:person@example.com", label: "mailto:person@example.com")))
        #expect(links.contains(.init(destination: "xmpp:person@example.com/chat", label: "xmpp:person@example.com/chat")))
    }

    @Test
    func `preserves common mark autolinks`() {
        let document = SwiftMarkdownParser().parse("<https://example.com/path>")
        let links = document.blocks.flatMap(links(in:))

        #expect(links == [.init(destination: "https://example.com/path", label: "https://example.com/path")])
    }

    @Test
    func `parses strikethrough`() {
        let document = SwiftMarkdownParser().parse("Text with ~deleted~ content")

        guard case let .paragraph(_, inlines) = document.blocks.first else {
            Issue.record("Expected paragraph")
            return
        }

        #expect(inlines.contains(.strikethrough([.text("deleted")])))
    }

    @Test
    func `parses malformed and unicode markdown without dropping text`() {
        let document = SwiftMarkdownParser().parse("Hello **unfinished Привіт 👋 \\*literal")

        guard case let .paragraph(_, inlines) = document.blocks.first else {
            Issue.record("Expected paragraph")
            return
        }

        #expect(plainText(in: inlines).contains("Hello **unfinished Привіт 👋 *literal"))
        #expect(!inlines.isEmpty)
    }

    @Test
    func `parses empty document`() {
        let document = SwiftMarkdownParser().parse("")

        #expect(document.blocks.isEmpty)
    }

    @Test
    func `parses large document`() {
        let markdown = (0..<500)
            .map { "- Item \($0)" }
            .joined(separator: "\n")

        let document = SwiftMarkdownParser().parse(markdown)

        guard case let .unorderedList(_, items) = document.blocks.first else {
            Issue.record("Expected unordered list")
            return
        }

        #expect(items.count == 500)
        #expect(document.renderRows.count == 500)
    }

    @Test
    func `flattens nested lists into stable render rows`() {
        let nestedList = MarkdownBlock.unorderedList(
            id: "nested-list",
            items: [
                MarkdownListItem(
                    id: "nested-item",
                    taskState: nil,
                    blocks: [
                        .paragraph(id: "nested-paragraph", [.text("Nested")])
                    ]
                )
            ]
        )
        let document = NotraMarkdownDocument(
            blocks: [
                .unorderedList(
                    id: "list",
                    items: [
                        MarkdownListItem(
                            id: "item",
                            taskState: .unchecked,
                            blocks: [
                                .paragraph(id: "paragraph", [.text("Item")]),
                                nestedList
                            ]
                        )
                    ]
                )
            ]
        )

        #expect(document.renderRows.map(\.id) == ["paragraph", "nested-paragraph"])
        #expect(document.renderRows[0].nestingLevel == 0)
        #expect(document.renderRows[1].nestingLevel == 1)
        #expect(document.renderRows[0].isInsideListItem)
        #expect(document.renderRows[1].isInsideListItem)

        guard case .task(.unchecked) = document.renderRows[0].marker,
              case .unordered(1) = document.renderRows[1].marker
        else {
            Issue.record("Expected stable list markers in flattened rows")
            return
        }
    }

    @Test
    func `preview style preserves legacy colors when editor theme is disabled`() {
        let legacyStyle = MarkdownStyle.notra(previewFontName: AppearanceFont.defaultName)
        let disabledThemeStyle = MarkdownStyle.notra(previewFontName: AppearanceFont.defaultName, theme: nil)

        #expect(disabledThemeStyle == legacyStyle)
    }

    @Test
    func `preview style uses editor theme colors when enabled`() {
        let theme = MarkdownTheme.light
        let style = MarkdownStyle.notra(previewFontName: AppearanceFont.defaultName, theme: theme)

        #expect(style.textColor == theme.preview.body.color)
        #expect(style.headingColor == theme.preview.headingPrimary.color)
        #expect(style.linkColor == theme.preview.link.color)
        #expect(style.markerColor == theme.preview.listMarker.color)
        #expect(style.quoteAccentColor == theme.preview.blockquoteIndicator.color)
        #expect(style.codeTextColor == theme.preview.inlineCode.color)
    }

    @Test
    func `themed preview style preserves preview font selection`() {
        let style = MarkdownStyle.notra(previewFontName: "Helvetica", theme: .dark)

        #expect(style.previewFontName == "Helvetica")
    }

    @Test
    func `preview style keeps code typography monospaced`() {
        let style = MarkdownStyle.notra(previewFontName: AppearanceFont.defaultName)

        #expect(style.codeBlockFont == .system(.body, design: .monospaced))
        #expect(style.inlineCodeFont == .system(.callout, design: .monospaced))
    }

    @Test
    func `preview model keeps most recent parse result`() async throws {
        let model = MarkdownPreviewModel(parser: Self.delayedMarkdownParser)

        model.update(markdown: "slow")
        try await Task.sleep(for: .milliseconds(20))
        model.update(markdown: "fast")

        for _ in 0..<20 {
            if parsedParagraphText(in: model.state) == "fast" {
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(parsedParagraphText(in: model.state) == "fast")
        try await Task.sleep(for: .milliseconds(250))
        #expect(parsedParagraphText(in: model.state) == "fast")
    }

    private struct ParsedLink: Equatable {
        let destination: String
        let label: String
    }

    private nonisolated static func delayedMarkdownParser(_ markdown: String) -> NotraMarkdownDocument {
            if markdown == "slow" {
                Thread.sleep(forTimeInterval: 0.2)
            }

            return NotraMarkdownDocument(
                blocks: [
                    .paragraph(id: markdown, [.text(markdown)])
                ]
            )
    }

    private func parsedParagraphText(in state: MarkdownPreviewModel.State) -> String? {
        guard case let .parsed(document) = state,
              case let .paragraph(_, inlines) = document.blocks.first
        else {
            return nil
        }

        return plainText(in: inlines)
    }

    private func firstTable(in document: NotraMarkdownDocument) -> MarkdownTable? {
        for block in document.blocks {
            if case let .table(_, table) = block {
                return table
            }
        }

        return nil
    }

    private func links(in block: MarkdownBlock) -> [ParsedLink] {
        switch block {
        case let .paragraph(_, inlines),
             let .heading(_, _, inlines):
            links(in: inlines)
        case let .unorderedList(_, items),
             let .orderedList(_, _, items):
            items.flatMap { item in
                item.blocks.flatMap(links(in:))
            }
        case let .blockQuote(_, blocks):
            blocks.flatMap(links(in:))
        case let .table(_, table):
            table.header.flatMap { links(in: $0.inlines) } + table.rows.flatMap { row in
                row.cells.flatMap { links(in: $0.inlines) }
            }
        case .codeBlock,
             .horizontalRule:
            []
        }
    }

    private func links(in inlines: [MarkdownInline]) -> [ParsedLink] {
        inlines.flatMap { inline in
            switch inline {
            case let .link(destination, _, children):
                return [ParsedLink(destination: destination, label: plainText(in: children))]
            case let .strong(children),
                 let .emphasis(children),
                 let .strikethrough(children):
                return links(in: children)
            case .text,
                 .code,
                 .image,
                 .softBreak,
                 .lineBreak:
                return []
            }
        }
    }

    private func plainText(in inlines: [MarkdownInline]) -> String {
        inlines.map { inline in
            switch inline {
            case let .text(text),
                 let .code(text):
                text
            case let .strong(children),
                 let .emphasis(children),
                 let .strikethrough(children),
                 let .link(_, _, children):
                plainText(in: children)
            case let .image(_, _, alt):
                alt
            case .softBreak:
                " "
            case .lineBreak:
                "\n"
            }
        }
        .joined()
    }
}
