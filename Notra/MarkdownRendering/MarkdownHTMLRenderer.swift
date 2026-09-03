import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Describes the HTML and local resources consumed by one isolated WebKit document.
struct MarkdownHTMLDocument: Equatable {
    let html: String
    let assets: [String: URL]
    let attachments: [String: URL]
    let includedImageURLs: Set<URL>
}

/// Defines the two HTML surfaces while keeping their source Markdown semantics identical.
enum MarkdownHTMLRenderMode {
    case preview
    case pdf
}

/// Converts Notra's parsed Markdown model into escaped, self-contained HTML for WebKit.
struct MarkdownHTMLRenderer {
    private let style: MarkdownStyle
    private let mode: MarkdownHTMLRenderMode
    private let context: MarkdownRenderContext
    private var assets: [String: URL] = [:]
    private var attachments: [String: URL] = [:]
    private var includedImageURLs = Set<URL>()
    private var nextResourceID = 0

    init(style: MarkdownStyle, mode: MarkdownHTMLRenderMode, context: MarkdownRenderContext) {
        self.style = style
        self.mode = mode
        self.context = context
    }

    /// Builds a full document so WebKit owns one continuous selection and print layout surface.
    mutating func render(_ document: NotraMarkdownDocument) -> MarkdownHTMLDocument {
        let content = document.blocks.map { render($0) }.joined(separator: "\n")
        return MarkdownHTMLDocument(
            html: "<!doctype html><html><head><meta charset=\"utf-8\">\(stylesheet)</head><body>\(content)</body></html>",
            assets: assets,
            attachments: attachments,
            includedImageURLs: includedImageURLs
        )
    }
}

private extension MarkdownHTMLRenderer {
    var stylesheet: String {
        let theme = MarkdownWebTheme(theme: style.codeSyntaxTheme)
        let fontFamily = cssString(style.previewFontName.isEmpty ? "-apple-system" : style.previewFontName)

        return """
        <style>
        :root { color-scheme: light dark; }
        html, body { margin: 0; min-height: 100%; background: transparent; }
        body { box-sizing: border-box; padding: 24px; color: \(theme.bodyText); }
        body { font: 17px \(fontFamily), -apple-system, sans-serif; line-height: 1.35; }
        h1, h2 { color: \(theme.headingPrimary); font-weight: 600; line-height: 1.2; }
        h3 { color: \(theme.headingSecondary); font-weight: 600; line-height: 1.2; }
        h4, h5, h6 { color: \(theme.headingTertiary); font-weight: 600; line-height: 1.2; }
        h1 { font-size: 34px; margin: 24px 0 16px; border-bottom: 1px solid \(theme.border); padding-bottom: 8px; }
        h2 { font-size: 25.5px; margin: 24px 0 16px; border-bottom: 1px solid \(theme.border); padding-bottom: 8px; }
        h3 { font-size: 21.25px; margin: 16px 0; } h4 { font-size: 17px; margin: 16px 0; }
        h5 { font-size: 14.875px; margin: 16px 0; } h6 { font-size: 14.45px; margin: 16px 0; }
        p { margin: 0 0 16px; } ul, ol { margin: 0 0 16px; padding-left: 24px; } li { margin: 0 0 4px; }
        li::marker { color: \(theme.listMarker); }
        .task-item { list-style: none; }
        .task-checkbox { margin: 0 6px 0 0; vertical-align: baseline; }
        blockquote { border-left: 4px solid \(theme.quoteAccent); color: \(theme.quoteText); margin: 0 0 16px; padding-left: 12px; }
        a { color: \(theme.linkText); } code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
        strong { color: \(theme.boldText); } em { color: \(theme.italicText); } del { color: \(theme.strikethroughText); }
        .inline-code { color: \(theme.inlineCodeText); padding: 1px 4px; border-radius: 4px; }
        .inline-code { background: \(theme.inlineCodeBackground); }
        pre { margin: 0 0 16px; padding: 16px; overflow-x: auto; border-radius: 6px; }
        pre { background: color-mix(in srgb, currentColor 10%, transparent); white-space: pre-wrap; }
        pre code { color: \(theme.codeBlockText); }
        .code-comment { color: \(theme.codeComment); }
        .code-keyword { color: \(theme.codeKeyword); }
        .code-string { color: \(theme.codeString); }
        .code-number { color: \(theme.codeNumber); }
        .code-type { color: \(theme.codeType); }
        .code-function { color: \(theme.codeFunction); }
        .code-operator { color: \(theme.codeOperator); }
        .code-tag { color: \(theme.codeTag); }
        .code-attribute { color: \(theme.codeAttribute); }
        .code-constant { color: \(theme.codeConstant); }
        hr { border: 0; border-top: 1px solid \(theme.horizontalRule); margin: 0 0 16px; }
        table { border-collapse: separate; border-spacing: 0; border: 1px solid \(theme.border); }
        table { border-radius: 6px; margin: 0 0 16px; min-width: 100%; overflow: hidden; }
        th, td { border-right: 1px solid \(theme.border); border-bottom: 1px solid \(theme.border); }
        th, td { padding: 8px; text-align: left; vertical-align: top; }
        th:last-child, td:last-child { border-right: 0; }
        tr:last-child td { border-bottom: 0; }
        th { background: color-mix(in srgb, currentColor 8%, transparent); }
        .markdown-image { display: block; max-width: 100%; height: auto; margin: 8px 0; }
        .markdown-image { break-inside: avoid-page; page-break-inside: avoid; }
        .image-placeholder, .attachment { display: block; margin: 8px 0; padding: 10px; border-radius: 6px; }
        .image-placeholder, .attachment { color: \(theme.secondaryText); }
        .image-placeholder, .attachment { background: color-mix(in srgb, currentColor 8%, transparent); }
        @media print { @page { size: 595.2756pt 841.8898pt; margin: 48pt; } body { padding: 0; color: #000; background: #fff; }
        .markdown-image { max-width: 499.2756pt; max-height: 745.8898pt; object-fit: contain; }
        .markdown-image { break-inside: avoid-page; page-break-inside: avoid; }
        table, tr { break-inside: avoid-page; page-break-inside: avoid; } }
        </style>
        """
    }

    mutating func render(_ block: MarkdownBlock) -> String {
        switch block {
        case let .paragraph(_, inlines):
            return "<p>\(render(inlines))</p>"
        case let .heading(_, level, inlines):
            let safeLevel = min(max(level, 1), 6)
            return "<h\(safeLevel)>\(render(inlines))</h\(safeLevel)>"
        case let .unorderedList(_, items):
            return "<ul>\(items.map { render($0) }.joined())</ul>"
        case let .orderedList(_, start, items):
            return "<ol start=\"\(start)\">\(items.map { render($0) }.joined())</ol>"
        case let .blockQuote(_, blocks):
            return "<blockquote>\(blocks.map { render($0) }.joined())</blockquote>"
        case let .codeBlock(_, language, code):
            return "<pre><code>\(renderCode(code, language: language))</code></pre>"
        case let .table(_, table):
            return render(table)
        case .horizontalRule:
            return "<hr>"
        }
    }

    mutating func render(_ item: MarkdownListItem) -> String {
        let checkbox = switch item.taskState {
        case .checked:
            "<input class=\"task-checkbox\" type=\"checkbox\" checked disabled>"
        case .unchecked:
            "<input class=\"task-checkbox\" type=\"checkbox\" disabled>"
        case nil:
            ""
        }

        guard item.taskState != nil else {
            return "<li>\(item.blocks.map { render($0) }.joined())</li>"
        }

        if case let .paragraph(_, inlines)? = item.blocks.first {
            let nestedBlocks = item.blocks.dropFirst().map { render($0) }.joined()
            return "<li class=\"task-item\">\(checkbox)<span>\(render(inlines))</span>\(nestedBlocks)</li>"
        }

        return "<li class=\"task-item\">\(checkbox)\(item.blocks.map { render($0) }.joined())</li>"
    }

    mutating func render(_ table: MarkdownTable) -> String {
        let header = table.header.enumerated().map { index, cell in
            "<th style=\"text-align:\(cssAlignment(table.columnAlignments[safe: index]))\">\(render(cell.inlines))</th>"
        }.joined()
        let rows = table.rows.map { row in
            let cells = row.cells.enumerated().map { pair in
                let index = pair.offset
                let cell = pair.element
                return "<td style=\"text-align:\(cssAlignment(table.columnAlignments[safe: index]))\">\(render(cell.inlines))</td>"
            }.joined()
            return "<tr>\(cells)" + "</tr>"
        }.joined()
        return "<table><thead><tr>\(header)</tr></thead><tbody>\(rows)</tbody></table>"
    }

    mutating func render(_ inlines: [MarkdownInline]) -> String {
        inlines.map { render($0) }.joined()
    }

    mutating func render(_ inline: MarkdownInline) -> String {
        switch inline {
        case let .text(text):
            escape(text)
        case let .strong(children):
            "<strong>\(render(children))</strong>"
        case let .emphasis(children):
            "<em>\(render(children))</em>"
        case let .strikethrough(children):
            "<del>\(render(children))</del>"
        case let .code(code):
            "<code class=\"inline-code\">\(escape(code))</code>"
        case let .link(destination, _, children):
            renderLink(destination: destination, children: children)
        case let .image(source, _, alt):
            renderImage(source: source, alt: alt)
        case .softBreak:
            " "
        case .lineBreak:
            "<br>"
        }
    }

    mutating func renderLink(destination: String, children: [MarkdownInline]) -> String {
        if let url = attachmentURL(for: destination) {
            let id = registerAttachment(url)
            return "<a class=\"attachment\" href=\"notra-attachment://attachment/\(id)\">\(render(children))</a>"
        }

        guard let url = resolvedLinkURL(destination) else {
            return render(children)
        }
        return "<a href=\"\(escapeAttribute(url.absoluteString))\">\(render(children))</a>"
    }

    mutating func renderImage(source: String?, alt: String) -> String {
        guard let source,
              let url = MarkdownAttachmentReferences.resolve(source, assetBaseURL: context.assetBaseURL)
        else {
            return mode == .preview ? placeholder(alt) : ""
        }

        if url.isFileURL {
            guard isImage(url), mode == .preview || canDecodeImage(url) else {
                return mode == .preview ? placeholder(alt) : ""
            }
            let id = registerAsset(url)
            if mode == .pdf {
                includedImageURLs.insert(url.notraCanonicalFileURL)
            }
            return "<img class=\"markdown-image\" src=\"notra-asset://asset/\(id)\" alt=\"\(escapeAttribute(alt))\">"
        }

        guard mode == .preview, url.scheme == "http" || url.scheme == "https" else {
            return mode == .preview ? placeholder(alt) : ""
        }
        return "<img class=\"markdown-image\" src=\"\(escapeAttribute(url.absoluteString))\" alt=\"\(escapeAttribute(alt))\">"
    }

    func renderCode(_ code: String, language: String?) -> String {
        guard style.codeSyntaxTheme != nil,
              let language,
              let parsedLanguage = MarkdownCodeLanguage(fenceTag: language)
        else {
            return escape(code)
        }

        let theme = MarkdownWebTheme(theme: style.codeSyntaxTheme)
        let spans = MarkdownCodeSyntaxHighlighter().spans(in: code, language: parsedLanguage)
        var result = ""
        var cursor = code.startIndex
        for span in spans {
            result += escape(String(code[cursor..<span.range.lowerBound]))
            let className = codeClass(for: span.role)
            let colour = theme.codeColour(for: span.role)
            result += "<span class=\"\(className)\" style=\"color:\(colour)\">\(escape(String(code[span.range])))</span>"
            cursor = span.range.upperBound
        }
        result += escape(String(code[cursor...]))
        return result
    }

    func codeClass(for role: MarkdownCodeHighlightRole) -> String {
        switch role {
        case .comment: "code-comment"
        case .keyword: "code-keyword"
        case .string: "code-string"
        case .number: "code-number"
        case .type: "code-type"
        case .function: "code-function"
        case .operator: "code-operator"
        case .tag: "code-tag"
        case .attribute: "code-attribute"
        case .constant: "code-constant"
        }
    }

    func cssAlignment(_ alignment: MarkdownTableAlignment?) -> String {
        switch alignment {
        case .center: "center"
        case .trailing: "right"
        case .leading, nil: "left"
        }
    }

    func resolvedLinkURL(_ destination: String) -> URL? {
        if let absoluteURL = URL(string: destination), absoluteURL.scheme != nil {
            return absoluteURL
        }
        if destination.hasPrefix("#") {
            return URL(string: destination)
        }
        return URL(string: destination, relativeTo: context.noteURL)?.absoluteURL
    }

    func isImage(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey])
        guard values?.isRegularFile == true else {
            return false
        }
        let contentType = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
        return TextBundleAssetKind(contentType: contentType, filename: url.lastPathComponent).isImage
    }

    func isAttachment(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey])
        let contentType = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
        return TextBundleAssetKind(contentType: contentType, filename: url.lastPathComponent) == .attachment
    }

    func attachmentURL(for destination: String) -> URL? {
        guard let url = MarkdownAttachmentReferences.resolve(destination, assetBaseURL: context.assetBaseURL),
              url.isFileURL,
              isAttachment(url)
        else {
            return nil
        }
        return url
    }

    func canDecodeImage(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return false
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }

    mutating func registerAsset(_ url: URL) -> String {
        let id = "resource-\(nextResourceID)"
        nextResourceID += 1
        assets[id] = url
        return id
    }

    mutating func registerAttachment(_ url: URL) -> String {
        let id = "attachment-\(nextResourceID)"
        nextResourceID += 1
        attachments[id] = url
        return id
    }

    func placeholder(_ alt: String) -> String {
        "<span class=\"image-placeholder\">\(escape(alt.isEmpty ? "Image" : alt))</span>"
    }

    func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    func escapeAttribute(_ string: String) -> String {
        escape(string).replacingOccurrences(of: "\"", with: "&quot;")
    }

    func cssString(_ string: String) -> String {
        "'\(string.replacingOccurrences(of: "'", with: "\\\\'"))'"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }
        return self[index]
    }
}
