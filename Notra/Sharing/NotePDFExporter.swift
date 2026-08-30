import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Captures the unsaved note content and render options used for one PDF export.
struct NotePDFSnapshot: Equatable, Sendable {
    let markdown: String
    let noteURL: URL
    let previewFontName: String
    let previewUsesEditorTheme: Bool
    let isDarkMode: Bool
    let suggestedFilename: String
}

/// Failure cases for temporary PDF rendering and file creation.
enum NotePDFExporterError: Error {
    case unableToCreatePDF
    case unableToRenderPDF
}

/// Renders a paginated A4 PDF from the same Markdown view used by preview.
@MainActor
struct NotePDFExporter {
    static let pageSize = CGSize(width: 595.2756, height: 841.8898)
    static let pageMargin: CGFloat = 48

    func export(snapshot: NotePDFSnapshot) throws -> NotePDFShareItem {
        let context = MarkdownRenderContext.textBundle(noteURL: snapshot.noteURL)
        let document = SwiftMarkdownParser().parse(snapshot.markdown)
        let preloadedImages = preloadImages(in: document, context: context)
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let filename = Self.sanitizedFilename(snapshot.suggestedFilename)
        let fileURL = directoryURL.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try render(
                document: document,
                context: context,
                preloadedImages: preloadedImages,
                snapshot: snapshot,
                to: fileURL
            )
            return NotePDFShareItem(
                fileURL: fileURL,
                suggestedFilename: filename,
                includedImageURLs: Set(preloadedImages.keys)
            )
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            throw error
        }
    }

    static func sanitizedFilename(_ filename: String) -> String {
        NoteExportFilename.sanitizedFilename(filename, fileExtension: "pdf")
    }

    static func preloadableImageURLs(
        in document: NotraMarkdownDocument,
        context: MarkdownRenderContext
    ) -> Set<URL> {
        var sources = Set<String>()
        collectImageSources(from: document.blocks, into: &sources)

        return Set(sources.compactMap { source in
            guard let url = MarkdownAttachmentReferences.resolve(
                source,
                assetBaseURL: context.assetBaseURL
            ),
                url.isFileURL,
                isImageAsset(url)
            else {
                return nil
            }

            return url.notraCanonicalFileURL
        })
    }
}

private extension NotePDFExporter {
    func preloadImages(
        in document: NotraMarkdownDocument,
        context: MarkdownRenderContext
    ) -> [URL: CGImage] {
        Self.preloadableImageURLs(in: document, context: context).reduce(into: [:]) { result, url in
            guard let image = decodedImage(at: url) else {
                return
            }
            result[url] = image
        }
    }

    func render(
        document: NotraMarkdownDocument,
        context: MarkdownRenderContext,
        preloadedImages: [URL: CGImage],
        snapshot: NotePDFSnapshot,
        to fileURL: URL
    ) throws {
        let theme = snapshot.previewUsesEditorTheme
            ? (snapshot.isDarkMode ? MarkdownHighlightTheme.tokyoNight : MarkdownHighlightTheme.light)
            : nil
        let style = MarkdownStyle.notra(
            previewFontName: snapshot.previewFontName,
            theme: theme,
            renderMode: .pdf
        )
        let input = MarkdownRenderInput(
            markdown: snapshot.markdown,
            context: context,
            mode: .pdf
        )
        let documentView = MarkdownDocumentView(
            input: input,
            eagerDocument: document,
            preloadedImages: preloadedImages
        )
        .environment(\.markdownStyle, style)
        .environment(\.secondaryBackgroundFill, .printable)
        .frame(width: Self.pageSize.width - 2 * Self.pageMargin, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)

        let renderer = ImageRenderer(content: documentView)
        renderer.proposedSize = ProposedViewSize(
            width: Self.pageSize.width - 2 * Self.pageMargin,
            height: nil
        )
        renderer.scale = 1
        renderer.isOpaque = true

        var mediaBox = CGRect(origin: .zero, size: Self.pageSize)
        guard let pdfContext = CGContext(
            fileURL as CFURL,
            mediaBox: &mediaBox,
            nil
        ) else {
            throw NotePDFExporterError.unableToCreatePDF
        }

        var renderError: Error?
        renderer.render { size, render in
            guard size.width > 0, size.height.isFinite, size.height >= 0 else {
                renderError = NotePDFExporterError.unableToRenderPDF
                return
            }

            let contentHeight = Self.pageSize.height - 2 * Self.pageMargin
            let pageCount = max(1, Int(ceil(max(size.height, 1) / contentHeight)))
            for page in 0..<pageCount {
                pdfContext.beginPDFPage([
                    kCGPDFContextMediaBox as String: Self.pageSize
                ] as CFDictionary)
                pdfContext.saveGState()
                pdfContext.setFillColor(CGColor(gray: 1, alpha: 1))
                pdfContext.fill(CGRect(origin: .zero, size: Self.pageSize))
                pdfContext.clip(to: CGRect(
                    x: Self.pageMargin,
                    y: Self.pageMargin,
                    width: Self.pageSize.width - 2 * Self.pageMargin,
                    height: contentHeight
                ))

                let sourceEnd = max(0, size.height - CGFloat(page) * contentHeight)
                let sourceStart = max(0, sourceEnd - contentHeight)
                let sourceHeight = sourceEnd - sourceStart
                pdfContext.translateBy(
                    x: Self.pageMargin,
                    y: Self.pageMargin + contentHeight - sourceHeight - sourceStart
                )
                render(pdfContext)
                pdfContext.restoreGState()
                pdfContext.endPDFPage()
            }
        }
        pdfContext.closePDF()

        if let renderError {
            throw renderError
        }
        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard FileManager.default.fileExists(atPath: fileURL.path),
              fileSize > 0
        else {
            throw NotePDFExporterError.unableToRenderPDF
        }
    }

    func decodedImage(at url: URL) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        return CGImageSourceCreateImageAtIndex(
            source,
            0,
            [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        )
    }

    static func isImageAsset(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]),
              values.isRegularFile == true
        else {
            return false
        }

        let contentType = values.contentType ?? UTType(filenameExtension: url.pathExtension)
        return TextBundleAssetKind(contentType: contentType, filename: url.lastPathComponent).isImage
    }

    static func collectImageSources(
        from blocks: [MarkdownBlock],
        into sources: inout Set<String>
    ) {
        for block in blocks {
            switch block {
            case let .paragraph(_, inlines), let .heading(_, _, inlines):
                collectImageSources(from: inlines, into: &sources)
            case let .unorderedList(_, items), let .orderedList(_, _, items):
                for item in items {
                    collectImageSources(from: item.blocks, into: &sources)
                }
            case let .blockQuote(_, nestedBlocks):
                collectImageSources(from: nestedBlocks, into: &sources)
            case let .table(_, table):
                collectImageSources(from: table.header, into: &sources)
                for row in table.rows {
                    collectImageSources(from: row.cells, into: &sources)
                }
            case .codeBlock, .horizontalRule:
                break
            }
        }
    }

    static func collectImageSources(
        from cells: [MarkdownTableCell],
        into sources: inout Set<String>
    ) {
        for cell in cells {
            collectImageSources(from: cell.inlines, into: &sources)
        }
    }

    static func collectImageSources(
        from inlines: [MarkdownInline],
        into sources: inout Set<String>
    ) {
        for inline in inlines {
            switch inline {
            case let .image(source, _, _):
                if let source {
                    sources.insert(source)
                }
            case let .strong(children), let .emphasis(children), let .strikethrough(children):
                collectImageSources(from: children, into: &sources)
            case let .link(_, _, children):
                collectImageSources(from: children, into: &sources)
            case .text, .code, .softBreak, .lineBreak:
                break
            }
        }
    }
}
