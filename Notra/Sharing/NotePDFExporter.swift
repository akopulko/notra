import CoreGraphics
import Foundation
import WebKit

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

/// Renders a paginated A4 PDF from the same HTML document used by the interactive preview.
@MainActor
struct NotePDFExporter {
    static let pageSize = CGSize(width: 595.2756, height: 841.8898)
    static let pageMargin: CGFloat = 48

    /// Generates WebKit PDF data only after the isolated HTML document has completed loading.
    func export(snapshot: NotePDFSnapshot) async throws -> NotePDFShareItem {
        let context = MarkdownRenderContext.textBundle(noteURL: snapshot.noteURL)
        let document = SwiftMarkdownParser().parse(snapshot.markdown)
        let theme = snapshot.previewUsesEditorTheme
            ? (snapshot.isDarkMode ? MarkdownHighlightTheme.tokyoNight : MarkdownHighlightTheme.light)
            : nil
        let style = MarkdownStyle.notra(
            previewFontName: snapshot.previewFontName,
            theme: theme,
            renderMode: .pdf
        )
        var htmlRenderer = MarkdownHTMLRenderer(style: style, mode: .pdf, context: context)
        let htmlDocument = htmlRenderer.render(document)
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let filename = Self.sanitizedFilename(snapshot.suggestedFilename)
        let fileURL = directoryURL.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let data = try await render(htmlDocument)
            try data.write(to: fileURL, options: .atomic)
            guard FileManager.default.fileExists(atPath: fileURL.path), !data.isEmpty else {
                throw NotePDFExporterError.unableToRenderPDF
            }
            return NotePDFShareItem(
                fileURL: fileURL,
                suggestedFilename: filename,
                includedImageURLs: htmlDocument.includedImageURLs
            )
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            throw error
        }
    }

    static func sanitizedFilename(_ filename: String) -> String {
        NoteExportFilename.sanitizedFilename(filename, fileExtension: "pdf")
    }
}

private extension NotePDFExporter {
    /// Uses an off-screen A4 viewport so printed CSS and the PDF media box share fixed dimensions.
    func render(_ document: MarkdownHTMLDocument) async throws -> Data {
        let assetHandler = MarkdownWebAssetHandler()
        assetHandler.update(document.assets)

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(assetHandler, forURLScheme: MarkdownWebAssetHandler.scheme)
        let webView = WKWebView(
            frame: CGRect(origin: .zero, size: Self.pageSize),
            configuration: configuration
        )
        let loader = PDFWebViewLoader()
        webView.navigationDelegate = loader
        try await loader.load(document.html, in: webView)

        do {
            return try await webView.pdf()
        } catch {
            throw NotePDFExporterError.unableToCreatePDF
        }
    }
}

/// Bridges WebKit's navigation callbacks into the exporter's structured concurrency flow.
@MainActor
private final class PDFWebViewLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ html: String, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        finish(with: .success(()))
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: any Error) {
        finish(with: .failure(error))
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: any Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<Void, Error>) {
        guard let continuation else {
            return
        }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
