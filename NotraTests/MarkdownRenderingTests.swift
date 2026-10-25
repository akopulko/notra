import Foundation
@testable import Notra
import SwiftUI
import Testing
import UniformTypeIdentifiers

enum MarkdownRenderingFixture {
    static let mixedDocument = """
    # Verification 👋

    1. Ordered fixture
       - Nested fixture

    - [ ] Task fixture

    > Quote fixture

    | Key | Value |
    | --- | --- |
    | Left fixture | Right fixture |

    ```mermaid
    flowchart TD
    A[Start fixture] --> B[End fixture]
    ```
    """
}

/// Checks parsing, styling, and HTML/PDF rendering behavior.
@MainActor
struct MarkdownRenderingTests {
    @Test
    func `web theme keeps normal text separate from code text`() {
        let webTheme = MarkdownWebTheme(theme: .dark)

        #expect(webTheme.bodyText == MarkdownTheme.dark.preview.body.hex)
        #expect(webTheme.codeBlockText == MarkdownTheme.dark.code.plain.hex)
        #expect(webTheme.inlineCodeText == MarkdownTheme.dark.preview.inlineCode.hex)
        #expect(webTheme.headingPrimary == MarkdownTheme.dark.preview.headingPrimary.hex)
        #expect(webTheme.codeColour(for: .keyword) == MarkdownTheme.dark.code.keyword.hex)
    }

    @Test
    func `web theme preserves system fallbacks when preview theming is disabled`() {
        let webTheme = MarkdownWebTheme(theme: nil)

        #expect(webTheme.bodyText == "CanvasText")
        #expect(webTheme.headingPrimary == "CanvasText")
        #expect(webTheme.linkText == "LinkText")
        #expect(webTheme.inlineCodeText == "CanvasText")
        #expect(webTheme.codeColour(for: .keyword) == "CanvasText")
    }

    @Test
    func `preview tag display truncates long names`() throws {
        let longTag = try #require(NoteTag("abcdefghijklmnop"))
        let shortTag = try #require(NoteTag("swift"))

        #expect(PreviewTagDisplay.text(for: longTag) == "#abcdefghijklmno...")
        #expect(PreviewTagDisplay.text(for: shortTag) == "#swift")
    }

    @Test
    func `html renderer applies preview and code semantic colours`() {
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

    @Test
    func `html renderer preserves inline image order`() throws {
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

    @Test
    func `html renderer creates matching heading anchors`() {
        let document = SwiftMarkdownParser().parse("""
        [First section](#first-section)
        [Equipment](#Equipment)

        # First section

        [Duplicate section](#first-section-1)

        ## First section

        ## Equipment
        """)
        var renderer = MarkdownHTMLRenderer(
            style: .notra(previewFontName: AppearanceFont.defaultName),
            mode: .preview,
            context: MarkdownRenderContext(
                noteURL: nil,
                assetBaseURL: URL(fileURLWithPath: "/tmp/example.textbundle/assets", isDirectory: true)
            )
        )

        let html = renderer.render(document).html

        #expect(html.contains("<a href=\"#first-section\">First section</a>"))
        #expect(html.contains("<a href=\"#equipment\">Equipment</a>"))
        #expect(html.contains("<h1 id=\"first-section\">First section</h1>"))
        #expect(html.contains("<h2 id=\"first-section-1\">First section</h2>"))
        #expect(html.contains("<h2 id=\"equipment\">Equipment</h2>"))
        #expect(html.contains("data-notra-heading-anchor=\"first-section\""))
        #expect(html.contains("data-notra-heading-anchor=\"first-section-1\""))
    }

    @Test
    func `preview heading sections respect hierarchy and container boundaries`() throws {
        let document = SwiftMarkdownParser().parse("""
        Intro boundary.

        ## Parent marker
        Parent body marker.

        #### Deep marker
        Deep body marker.

        ## Peer marker
        Peer body marker.

        # Root marker
        Root body marker.

        > ### Quote marker
        > Quote body marker.

        - Item marker

          ### List marker
          List body marker.

        Outside marker.
        """)
        var renderer = MarkdownHTMLRenderer(
            style: .notra(previewFontName: AppearanceFont.defaultName),
            mode: .preview,
            context: .empty
        )
        let html = renderer.render(document).html
        let intro = try #require(html.range(of: "Intro boundary.")?.lowerBound)
        let parent = try #require(html.range(of: "data-notra-heading-anchor=\"parent-marker\"")?.lowerBound)
        let deep = try #require(html.range(of: "data-notra-heading-anchor=\"deep-marker\"")?.lowerBound)
        let peer = try #require(html.range(of: "data-notra-heading-anchor=\"peer-marker\"")?.lowerBound)
        let root = try #require(html.range(of: "data-notra-heading-anchor=\"root-marker\"")?.lowerBound)
        let quote = try #require(html.range(of: "data-notra-heading-anchor=\"quote-marker\"")?.lowerBound)
        let list = try #require(html.range(of: "data-notra-heading-anchor=\"list-marker\"")?.lowerBound)
        let quoteStart = try #require(html.range(of: "<blockquote>")?.lowerBound)
        let quoteEnd = try #require(html.range(of: "</blockquote>")?.lowerBound)
        let listStart = try #require(html.range(of: "<ul>")?.lowerBound)
        let listEnd = try #require(html.range(of: "</ul>")?.lowerBound)

        #expect(intro < parent)
        #expect(parent < deep)
        #expect(deep < peer)
        #expect(peer < root)
        #expect(root < quoteStart)
        #expect(quoteStart < quote)
        #expect(quote < quoteEnd)
        #expect(quoteEnd < listStart)
        #expect(listStart < list)
        #expect(list < listEnd)
        let outside = try #require(html.range(of: "Outside marker.")?.lowerBound)
        let parentBody = try #require(html.range(of: "Parent body marker.")?.lowerBound)
        let deepBody = try #require(html.range(of: "Deep body marker.")?.lowerBound)
        let peerBody = try #require(html.range(of: "Peer body marker.")?.lowerBound)
        let rootBody = try #require(html.range(of: "Root body marker.")?.lowerBound)
        let quoteBody = try #require(html.range(of: "Quote body marker.")?.lowerBound)
        let listBody = try #require(html.range(of: "List body marker.")?.lowerBound)
        let deepEndRange = try #require(html.range(of: "</div></details>", range: deep..<peer))
        let deepEnd = deepEndRange.lowerBound
        let parentEnd = try #require(
            html.range(of: "</div></details>", range: deepEndRange.upperBound..<peer)?.lowerBound
        )
        let listItemEnd = try #require(html.range(of: "</li>", range: list..<listEnd)?.lowerBound)

        #expect(listEnd < outside)
        #expect(html.components(separatedBy: "<details class=\"notra-heading-section\"").count == 7)
        #expect(html.components(separatedBy: " open><summary>").count == 7)
        #expect(parent < parentBody && parentBody < deep)
        #expect(deep < deepBody && deepBody < deepEnd)
        #expect(deepEnd < parentEnd && parentEnd < peer)
        #expect(peer < peerBody && peerBody < root)
        #expect(root < rootBody && rootBody < quoteStart)
        #expect(quote < quoteBody && quoteBody < quoteEnd)
        #expect(list < listBody && listBody < listItemEnd && listItemEnd < listEnd)
    }

    @Test
    func `pdf headings remain non interactive`() {
        let document = SwiftMarkdownParser().parse("""
        Intro boundary.

        ## Parent marker
        Parent body marker.

        #### Deep marker
        Deep body marker.

        ## Peer marker
        Peer body marker.

        # Root marker
        Root body marker.

        > ### Quote marker
        > Quote body marker.

        - Item marker

          ### List marker
          List body marker.

        Outside marker.
        """)
        var renderer = MarkdownHTMLRenderer(
            style: .notra(previewFontName: AppearanceFont.defaultName),
            mode: .pdf,
            context: .empty
        )

        let html = renderer.render(document).html

        for marker in [
            "Intro boundary.", "Parent marker", "Parent body marker.", "Deep marker", "Deep body marker.",
            "Peer marker", "Peer body marker.", "Root marker", "Root body marker.", "Quote marker",
            "Quote body marker.", "Item marker", "List marker", "List body marker.", "Outside marker."
        ] {
            #expect(html.contains(marker))
        }
        #expect(!html.contains("<details"))
        #expect(!html.contains("notra-heading-section"))
    }

    @Test
    func `html renderer normalises heading anchor text`() {
        let document = SwiftMarkdownParser().parse("# API & Usage!")
        var renderer = MarkdownHTMLRenderer(
            style: .notra(previewFontName: AppearanceFont.defaultName),
            mode: .preview,
            context: .empty
        )

        let html = renderer.render(document).html

        #expect(html.contains("<h1 id=\"api-usage\">API &amp; Usage!</h1>"))
    }

    @Test
    func `checked task checkboxes use the preview italic colour`() {
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

    @Test
    func `preview constrains wide content without changing PDF layout`() {
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

    @Test
    func `preview code syntax theme follows the preview theme option`() {
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

    @Test
    func `pdf HTML uses A theme independent light A 4 layout`() {
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

    @Test
    func `pdf HTML includes remote images`() {
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
    func `preview HTML omits local non image attachments`() throws {
        let noteURL = URL.temporaryDirectory
            .appendingPathComponent("MarkdownRenderingTests-\(UUID().uuidString)")
            .appendingPathExtension(TextBundleNoteRepository.bundleExtension)
        let assetsURL = noteURL.appendingPathComponent(TextBundleNoteRepository.assetsFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: noteURL)
        }
        try Data("report".utf8).write(to: assetsURL.appendingPathComponent("report.pdf"))

        let document = SwiftMarkdownParser().parse(
            "Before [Report](assets/report.pdf) and ![Report](assets/report.pdf) After"
        )
        var renderer = MarkdownHTMLRenderer(
            style: .notra(previewFontName: AppearanceFont.defaultName),
            mode: .preview,
            context: .textBundle(noteURL: noteURL)
        )

        let html = renderer.render(document).html

        #expect(html.contains("Before"))
        #expect(html.contains("After"))
        #expect(!html.contains("Report"))
        #expect(!html.contains("notra-" + "attachment://"))
        #expect(!html.contains("class=\"attachment\""))
        #expect(!html.contains("<span class=\"image-placeholder\">"))
    }

    @Test
    func `preview attachment overlay model uses current markdown links`() throws {
        let noteURL = URL.temporaryDirectory
            .appendingPathComponent("MarkdownRenderingTests-\(UUID().uuidString)")
            .appendingPathExtension(TextBundleNoteRepository.bundleExtension)
        let assetsURL = noteURL.appendingPathComponent(TextBundleNoteRepository.assetsFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: noteURL)
        }

        let report = TextBundleAsset(
            url: assetsURL.appendingPathComponent("report.pdf"),
            contentType: .pdf,
            byteCount: 1,
            isLinked: false
        )
        let photo = TextBundleAsset(
            url: assetsURL.appendingPathComponent("photo.png"),
            contentType: .png,
            byteCount: 1,
            isLinked: true
        )
        let archive = TextBundleAsset(
            url: assetsURL.appendingPathComponent("archive.zip"),
            contentType: .zip,
            byteCount: 1,
            isLinked: false
        )
        let attachments = [archive, photo, report]

        let linked = PreviewAttachmentOverlayModel.linkedNonImageAttachments(
            from: attachments,
            markdown: "[Report](assets/report.pdf) ![Photo](assets/photo.png)",
            noteURL: noteURL
        )
        let noReportLink = PreviewAttachmentOverlayModel.linkedNonImageAttachments(
            from: attachments,
            markdown: "![Photo](assets/photo.png)",
            noteURL: noteURL
        )

        #expect(linked == [report])
        #expect(noReportLink.isEmpty)
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
        #expect(items.map(\.taskMarker) == [
            MarkdownTaskMarker(line: 1, column: 3, state: .unchecked),
            MarkdownTaskMarker(line: 2, column: 3, state: .checked)
        ])
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

        #expect(html.contains("<li class=\"task-item\"><input class=\"task-checkbox\" type=\"checkbox\" data-notra-task-line=\"1\" data-notra-task-column=\"3\" data-notra-task-state=\"unchecked\"><span>test 1</span></li>"))
        #expect(html.contains("<li class=\"task-item\"><input class=\"task-checkbox\" type=\"checkbox\" checked data-notra-task-line=\"2\" data-notra-task-column=\"3\" data-notra-task-state=\"checked\"><span>test 2</span></li>"))
        #expect(!html.contains("<li><input type=\"checkbox\""))
    }

    @Test
    func `formatted bare list item parses as an unchecked task with its paragraph text`() {
        let text = "- Item"
        let formatted = MarkdownFormatting.applyTodoResult(
            to: text,
            selection: text.startIndex..<text.endIndex
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
        let style = MarkdownStyle.notra(
            previewFontName: "Helvetica",
            previewFixedWidthFontName: "ExampleMono-Regular",
            theme: .dark
        )

        #expect(style.previewFontName == "Helvetica")
        #expect(style.previewFixedWidthFontName == "ExampleMono-Regular")
    }

    @Test
    func `preview style keeps code typography monospaced`() {
        let style = MarkdownStyle.notra(previewFontName: AppearanceFont.defaultName)

        #expect(style.codeBlockFont == .system(.body, design: .monospaced))
        #expect(style.inlineCodeFont == .system(.callout, design: .monospaced))
    }

    @Test
    func `preview fixed-width font styles inline and fenced code`() {
        let document = SwiftMarkdownParser().parse("""
        Inline `code`.

        ```swift
        let value = 1
        ```
        """)
        var renderer = MarkdownHTMLRenderer(
            style: .notra(
                previewFontName: AppearanceFont.defaultName,
                previewFixedWidthFontName: "Example Mono"
            ),
            mode: .preview,
            context: .empty
        )

        let html = renderer.render(document).html

        #expect(html.contains(
            "code { font-family: 'Example Mono', ui-monospace, SFMono-Regular, Menlo, monospace; }"
        ))
        #expect(html.contains("<code class=\"inline-code\">code</code>"))
        #expect(html.contains("<pre><code"))
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

    @Test
    func `mermaid fence uses local runtime and escaped source only for recognised tags`() {
        let document = SwiftMarkdownParser().parse("""
        ```mErMaId
        flowchart TD
        A["<script>alert(1)</script>"] --> B
        ```

        ```unknown
        <script>ordinary</script>
        ```
        """)
        var renderer = MarkdownHTMLRenderer(
            style: .notra(previewFontName: AppearanceFont.defaultName),
            mode: .preview,
            context: .empty
        )

        let html = renderer.render(document).html

        #expect(html.contains("notra-mermaid://bundle/mermaid.min.js"))
        #expect(html.contains("class=\"notra-mermaid\""))
        #expect(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        #expect(!html.contains("<script>alert(1)</script>"))
        #expect(html.contains("<pre><code>&lt;script&gt;ordinary&lt;/script&gt;"))
        #expect(html.contains("data-notra-render-mode=\"preview\""))
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
