import CoreGraphics
import Foundation
import PDFKit
import WebKit

/// Captures the browser-paginated document one A4 column at a time without redrawing PDF contents.
@MainActor
enum NotePDFPrintRenderer {
    static func render(
        webView: WKWebView,
        pageSize: CGSize
    ) async throws -> Data {
        // WebKit captures integral page coordinates; exact A4 bounds are restored on the PDF page below.
        let captureSize = CGSize(width: floor(pageSize.width), height: ceil(pageSize.height))
        let pageCount = try await pageCount(
            in: webView,
            pageWidth: captureSize.width
        )
        let output = PDFDocument()
        for pageIndex in 0..<pageCount {
            let configuration = WKPDFConfiguration()
            configuration.rect = CGRect(
                x: CGFloat(pageIndex) * captureSize.width,
                y: 0,
                width: captureSize.width,
                height: captureSize.height
            )
            configuration.allowTransparentBackground = false
            let data = try await webView.pdf(configuration: configuration)
            guard let pageDocument = PDFDocument(data: data),
                  let page = pageDocument.page(at: 0)
            else {
                throw NotePDFExporterError.unableToRenderPDF
            }
            let pageBounds = CGRect(origin: .zero, size: pageSize)
            page.setBounds(pageBounds, for: .mediaBox)
            page.setBounds(pageBounds, for: .cropBox)
            output.insert(page, at: output.pageCount)
        }

        guard let data = output.dataRepresentation(), !data.isEmpty else {
            throw NotePDFExporterError.unableToRenderPDF
        }
        return data
    }
}

private extension NotePDFPrintRenderer {
    static func pageCount(
        in webView: WKWebView,
        pageWidth: CGFloat
    ) async throws -> Int {
        let result = try await webView.callAsyncJavaScript(
            """
            const content = document.querySelector('.pdf-content');
            if (!content) { return 1; }
            const range = document.createRange();
            range.selectNodeContents(content);
            const contentLeft = content.getBoundingClientRect().left;
            const furthestRight = Array.from(range.getClientRects()).reduce(
                (maximum, rect) => Math.max(maximum, rect.right),
                contentLeft
            );
            const usedWidth = Math.max(0, furthestRight - contentLeft - 1);
            return Math.max(1, Math.floor(usedWidth / pageWidth) + 1);
            """,
            arguments: [
                "pageWidth": Double(pageWidth)
            ],
            contentWorld: .page
        )
        guard let number = result as? NSNumber,
              number.intValue > 0
        else {
            throw NotePDFExporterError.unableToRenderPDF
        }
        return number.intValue
    }
}
