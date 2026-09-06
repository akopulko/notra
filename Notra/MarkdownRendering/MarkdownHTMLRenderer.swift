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
    private var headingAnchorCounts: [String: Int] = [:]
    private var headingAnchorIDs: [String: String] = [:]
    private var headingAnchorsBySlug: [String: String] = [:]
    private var nextResourceID = 0

    init(style: MarkdownStyle, mode: MarkdownHTMLRenderMode, context: MarkdownRenderContext) {
        self.style = style
        self.mode = mode
        self.context = context
    }

    /// Builds a full document so WebKit owns one continuous selection and print layout surface.
    mutating func render(_ document: NotraMarkdownDocument) -> MarkdownHTMLDocument {
        headingAnchorCounts.removeAll(keepingCapacity: true)
        headingAnchorIDs.removeAll(keepingCapacity: true)
        headingAnchorsBySlug.removeAll(keepingCapacity: true)
        indexHeadingAnchors(in: document.blocks)
        let content = document.blocks.map { render($0) }.joined(separator: "\n")
        let body = mode == .pdf ? "<main class=\"pdf-content\">\(content)</main>" : content
        let head = "<meta charset=\"utf-8\">\(viewportMetadata)\(stylesheet)"
        return MarkdownHTMLDocument(
            html: "<!doctype html><html><head>\(head)</head><body>\(body)</body></html>",
            assets: assets,
            attachments: attachments,
            includedImageURLs: includedImageURLs
        )
    }
}

private extension MarkdownHTMLRenderer {
    var viewportMetadata: String {
        guard mode == .preview else {
            return ""
        }

        // Match CSS pixels to the iOS viewport so WebKit does not scale a desktop-width page into the preview.
        return "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
    }

    var stylesheet: String {
        let theme = MarkdownWebTheme(theme: style.codeSyntaxTheme, printable: mode == .pdf)
        let fontFamily = cssString(style.previewFontName.isEmpty ? "-apple-system" : style.previewFontName)

        return """
        <style>
        :root { color-scheme: \(mode == .pdf ? "only light" : "light dark"); }
        html, body { margin: 0; min-height: 100%; background: transparent; }
        \(previewWidthRules)
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
        \(taskCheckboxRules(theme: theme))
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
        .pdf-image-container { display: block; max-width: 100%; break-inside: avoid-page; page-break-inside: avoid; }
        .image-placeholder, .attachment { display: block; margin: 8px 0; padding: 10px; border-radius: 6px; }
        .image-placeholder, .attachment { color: \(theme.secondaryText); }
        .image-placeholder, .attachment { background: color-mix(in srgb, currentColor 8%, transparent); }
        \(pdfLayoutRules)
        </style>
        """
    }

    var previewWidthRules: String {
        guard mode == .preview else {
            return ""
        }

        // Keep wide content inside the interactive viewport while allowing fenced code to scroll locally.
        return """
        html, body { width: 100%; max-width: 100%; overflow-x: hidden; }
        *, *::before, *::after { box-sizing: border-box; }
        body { overflow-wrap: anywhere; }
        pre { max-width: 100%; }
        pre, pre code { overflow-wrap: normal; }
        table { width: 100%; max-width: 100%; table-layout: fixed; }
        th, td { overflow-wrap: anywhere; }
        """
    }

    func taskCheckboxRules(theme: MarkdownWebTheme) -> String {
        guard mode == .preview else {
            return ""
        }

        // Native checkbox controls otherwise use the operating system accent colour instead of the preview theme.
        return ".task-checkbox:checked { accent-color: \(theme.italicText); }"
    }

    var pdfLayoutRules: String {
        guard mode == .pdf else {
            return ""
        }

        // Lay pages out as fixed-height browser columns so each captured region is exactly one A4 sheet.
        return """
        html, body { width: 595px; height: 842px; min-height: 842px; overflow: visible; }
        html, body { color-scheme: only light; background: #fff; }
        body { padding: 0; background: #fff; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        .pdf-content { position: absolute; left: 48px; top: 48px; width: 499px; height: 746px; }
        .pdf-content { column-width: 499px; column-gap: 96px; column-fill: auto; }
        pre { max-width: 100%; overflow: hidden; overflow-wrap: anywhere; }
        table { width: 100%; max-width: 100%; table-layout: fixed; }
        th, td { overflow-wrap: anywhere; }
        .pdf-image-container { break-inside: avoid-column; }
        .markdown-image { width: auto; max-width: 100%; height: auto; max-height: 746px; margin: 0; }
        tr { break-inside: avoid-column; }
        """
    }

    mutating func render(_ block: MarkdownBlock) -> String {
        switch block {
        case let .paragraph(_, inlines):
            return "<p>\(render(inlines))</p>"
        case let .heading(id, level, inlines):
            let safeLevel = min(max(level, 1), 6)
            let anchor = headingAnchorIDs[id] ?? headingSlug(for: plainText(inlines))
            return "<h\(safeLevel) id=\"\(anchor)\">\(render(inlines))</h\(safeLevel)>"
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

    mutating func headingAnchorID(for inlines: [MarkdownInline]) -> String {
        let base = headingSlug(for: plainText(inlines))
        let occurrence = headingAnchorCounts[base, default: 0]
        headingAnchorCounts[base] = occurrence + 1
        return occurrence == 0 ? base : "\(base)-\(occurrence)"
    }

    mutating func indexHeadingAnchors(in blocks: [MarkdownBlock]) {
        for block in blocks {
            switch block {
            case let .heading(id, _, inlines):
                let anchor = headingAnchorID(for: inlines)
                headingAnchorIDs[id] = anchor
                headingAnchorsBySlug[anchor] = anchor
            case let .unorderedList(_, items),
                 let .orderedList(_, _, items):
                for item in items {
                    indexHeadingAnchors(in: item.blocks)
                }
            case let .blockQuote(_, nestedBlocks):
                indexHeadingAnchors(in: nestedBlocks)
            case .paragraph, .codeBlock, .table, .horizontalRule:
                break
            }
        }
    }

    func headingSlug(for text: String) -> String {
        var slug = ""
        var pendingSeparator = false

        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                if pendingSeparator, !slug.isEmpty {
                    slug.append("-")
                }
                slug.append(character)
                pendingSeparator = false
            } else if character == "-" || character == "_" {
                slug.append(character)
                pendingSeparator = false
            } else if character.isWhitespace {
                pendingSeparator = true
            }
        }

        return slug.isEmpty ? "section" : slug
    }

    func plainText(_ inlines: [MarkdownInline]) -> String {
        inlines.map { inline in
            switch inline {
            case let .text(text), let .code(text):
                text
            case let .strong(children),
                 let .emphasis(children),
                 let .strikethrough(children),
                 let .link(_, _, children):
                plainText(children)
            case let .image(_, _, alt):
                alt
            case .softBreak, .lineBreak:
                " "
            }
        }.joined()
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
            renderLink(destination: canonicalAnchorDestination(destination), children: children)
        case let .image(source, _, alt):
            renderImage(source: source, alt: alt)
        case .softBreak:
            " "
        case .lineBreak:
            "<br>"
        }
    }

    mutating func renderLink(destination: String, children: [MarkdownInline]) -> String {
        if mode == .pdf, isPDFAssetLink(destination) {
            return ""
        }

        if let url = attachmentURL(for: destination) {
            let id = registerAttachment(url)
            return "<a class=\"attachment\" href=\"notra-attachment://attachment/\(id)\">\(render(children))</a>"
        }

        guard let url = resolvedLinkURL(destination) else {
            return render(children)
        }
        return "<a href=\"\(escapeAttribute(url.absoluteString))\">\(render(children))</a>"
    }

    func canonicalAnchorDestination(_ destination: String) -> String {
        guard destination.hasPrefix("#") else {
            return destination
        }

        let encodedFragment = String(destination.dropFirst())
        let fragment = encodedFragment.removingPercentEncoding ?? encodedFragment
        let slug = headingSlug(for: fragment)
        guard let anchor = headingAnchorsBySlug[slug] else {
            return destination
        }
        return "#\(anchor)"
    }

    func isPDFAssetLink(_ destination: String) -> Bool {
        guard let url = MarkdownAttachmentReferences.resolve(destination, assetBaseURL: context.assetBaseURL),
              url.isFileURL,
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        else {
            return false
        }
        return isImage(url) || isAttachment(url)
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
            let image = "<img class=\"markdown-image\" src=\"notra-asset://asset/\(id)\" alt=\"\(escapeAttribute(alt))\">"
            return mode == .pdf ? "<span class=\"pdf-image-container\">\(image)</span>" : image
        }

        guard url.scheme == "http" || url.scheme == "https" else {
            return mode == .preview ? placeholder(alt) : ""
        }
        let image = "<img class=\"markdown-image\" src=\"\(escapeAttribute(url.absoluteString))\" alt=\"\(escapeAttribute(alt))\">"
        return mode == .pdf ? "<span class=\"pdf-image-container\">\(image)</span>" : image
    }

    func renderCode(_ code: String, language: String?) -> String {
        guard style.codeSyntaxTheme != nil,
              let language,
              let parsedLanguage = MarkdownCodeLanguage(fenceTag: language)
        else {
            return escape(code)
        }

        let theme = MarkdownWebTheme(theme: style.codeSyntaxTheme, printable: mode == .pdf)
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
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey])
        guard values?.isRegularFile == true else {
            return false
        }
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
        let canonicalURL = url.notraCanonicalFileURL
        // WebKit caches custom-scheme responses by URL, so a per-document counter would leak images across notes.
        let encodedURL = Data(canonicalURL.absoluteString.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let id = "resource-\(encodedURL)"
        assets[id] = canonicalURL
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
