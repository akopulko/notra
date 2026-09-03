import SwiftUI
import UniformTypeIdentifiers
import WebKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Parses preview Markdown away from the view update path before handing one document to WebKit.
struct MarkdownWebPreview: View {
    @Environment(\.openURL) private var openURL
    @State private var model = MarkdownPreviewModel()

    let markdown: String
    let context: MarkdownRenderContext
    let style: MarkdownStyle
    let openAttachment: (URL) -> Void

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                Color.clear
            case let .parsed(document):
                MarkdownWebView(
                    document: htmlDocument(for: document),
                    openURL: { url in
                        openURL(url)
                    },
                    openAttachment: openAttachment
                )
            }
        }
        .task(id: markdown) {
            model.update(markdown: markdown)
        }
    }

    /// Keeps HTML generation deterministic from the parser-owned document model.
    private func htmlDocument(for document: NotraMarkdownDocument) -> MarkdownHTMLDocument {
        var renderer = MarkdownHTMLRenderer(style: style, mode: .preview, context: context)
        return renderer.render(document)
    }
}

// Hosts one browser document so selection can pass through every Markdown block.
#if os(iOS)
private struct MarkdownWebView: UIViewRepresentable {
    let document: MarkdownHTMLDocument
    let openURL: (URL) -> Void
    let openAttachment: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(openURL: openURL, openAttachment: openAttachment)
    }

    func makeUIView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(document: document, in: webView)
    }
}
#else
private struct MarkdownWebView: NSViewRepresentable {
    let document: MarkdownHTMLDocument
    let openURL: (URL) -> Void
    let openAttachment: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(openURL: openURL, openAttachment: openAttachment)
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(document: document, in: webView)
    }
}
#endif

/// Owns WebKit delegates and local-resource policy for both SwiftUI platform wrappers.
private final class Coordinator: NSObject, WKNavigationDelegate {
    private let assetHandler = MarkdownWebAssetHandler()
    private let openURL: (URL) -> Void
    private let openAttachment: (URL) -> Void
    private var renderedHTML: String?
    private var attachments: [String: URL] = [:]

    init(openURL: @escaping (URL) -> Void, openAttachment: @escaping (URL) -> Void) {
        self.openURL = openURL
        self.openAttachment = openAttachment
    }

    func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(assetHandler, forURLScheme: MarkdownWebAssetHandler.scheme)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // The document owns any local horizontal overflow, so the outer preview should remain vertically anchored.
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.isDirectionalLockEnabled = true
        #else
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        return webView
    }

    func update(document: MarkdownHTMLDocument, in webView: WKWebView) {
        assetHandler.update(document.assets)
        attachments = document.attachments
        guard renderedHTML != document.html else {
            return
        }
        renderedHTML = document.html
        webView.loadHTMLString(document.html, baseURL: nil)
    }

    func webView(
        _: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url
        else {
            decisionHandler(.allow)
            return
        }

        if let attachment = attachmentURL(for: url) {
            openAttachment(attachment)
            decisionHandler(.cancel)
            return
        }

        openURL(url)
        decisionHandler(.cancel)
    }

    private func attachmentURL(for url: URL) -> URL? {
        guard url.scheme == MarkdownWebAttachmentScheme.scheme,
              let id = url.pathComponents.last
        else {
            return nil
        }
        return attachments[id]
    }
}

/// Limits WebKit reads to resources already approved by TextBundle path resolution.
final class MarkdownWebAssetHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "notra-asset"

    private var assets: [String: URL] = [:]

    func update(_ assets: [String: URL]) {
        self.assets = assets
    }

    func webView(_: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let url = urlSchemeTask.request.url
        guard let url,
              url.host == "asset",
              let id = url.pathComponents.last,
              let assetURL = assets[id],
              let data = try? Data(contentsOf: assetURL)
        else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let contentType = UTType(filenameExtension: assetURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let response = URLResponse(
            url: url,
            mimeType: contentType,
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_: WKWebView, stop _: any WKURLSchemeTask) {}
}

/// Separates attachment activation from the asset-serving URL scheme.
private enum MarkdownWebAttachmentScheme {
    static let scheme = "notra-attachment"
}
