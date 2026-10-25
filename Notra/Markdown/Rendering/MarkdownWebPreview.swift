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
    let toggleTask: (MarkdownTaskMarker, MarkdownTaskState) -> Void

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                Color.clear
            case .parsed:
                if let document = model.htmlDocument {
                    MarkdownWebView(
                        document: document,
                        openURL: { url in
                            openURL(url)
                        },
                        toggleTask: toggleTask
                    )
                } else {
                    Color.clear
                }
            }
        }
        .task(id: PreviewRequestID(markdown: markdown, context: context, style: style)) {
            model.update(markdown: markdown, context: context, style: style)
        }
    }

    private struct PreviewRequestID: Equatable {
        let markdown: String
        let context: MarkdownRenderContext
        let style: MarkdownStyle
    }
}

// Hosts one browser document so selection can pass through every Markdown block.
#if os(iOS)
private struct MarkdownWebView: UIViewRepresentable {
    let document: MarkdownHTMLDocument
    let openURL: (URL) -> Void
    let toggleTask: (MarkdownTaskMarker, MarkdownTaskState) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(openURL: openURL, toggleTask: toggleTask)
    }

    func makeUIView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(document: document, in: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.cancelPendingReadiness()
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.taskToggleMessageName
        )
    }
}
#else
private struct MarkdownWebView: NSViewRepresentable {
    let document: MarkdownHTMLDocument
    let openURL: (URL) -> Void
    let toggleTask: (MarkdownTaskMarker, MarkdownTaskState) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(openURL: openURL, toggleTask: toggleTask)
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(document: document, in: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.cancelPendingReadiness()
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.taskToggleMessageName
        )
    }
}

/// Removes WebKit's page reload command from the read-only Markdown preview menu.
private final class MarkdownPreviewWebView: WKWebView {
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        // WebKit owns the target and may use private selectors, so retain the
        // visible-title check that its generated menu exposes consistently.
        for item in menu.items where isReloadItem(item) {
            menu.removeItem(item)
        }
    }

    private func isReloadItem(_ item: NSMenuItem) -> Bool {
        if item.title.localizedCaseInsensitiveCompare("Reload") == .orderedSame {
            return true
        }
        return item.action.map {
            NSStringFromSelector($0).localizedCaseInsensitiveContains("reload")
        } == true
    }
}
#endif

/// Owns WebKit delegates and local-resource policy for both SwiftUI platform wrappers.
final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private let assetHandler = MarkdownWebAssetHandler()
    private let openURL: (URL) -> Void
    private let toggleTask: (MarkdownTaskMarker, MarkdownTaskState) -> Void
    private var renderedHTML: String?
    private var documentGeneration = 0
    private struct PreviewState {
        let scrollOffset: Double
        let collapsedHeadingAnchors: [String]
    }

    private var pendingPreviewState: PreviewState?

    static let taskToggleMessageName = "notraTaskToggle"

    init(
        openURL: @escaping (URL) -> Void,
        toggleTask: @escaping (MarkdownTaskMarker, MarkdownTaskState) -> Void
    ) {
        self.openURL = openURL
        self.toggleTask = toggleTask
    }

    func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        MarkdownMermaidRuntime.configure(configuration)
        configuration.setURLSchemeHandler(assetHandler, forURLScheme: MarkdownWebAssetHandler.scheme)
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.anchorNavigationScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.taskCheckboxScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        configuration.userContentController.add(self, name: Self.taskToggleMessageName)
        #if os(macOS)
        let webView = MarkdownPreviewWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        #else
        let webView = WKWebView(frame: .zero, configuration: configuration)
        #endif
        webView.navigationDelegate = self
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.isDirectionalLockEnabled = true
        #else
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        return webView
    }

    /// WebKit normalises fragment URLs loaded from an in-memory document, so
    /// resolve same-note links in the document before navigation delegates see them.
    private static let anchorNavigationScript = """
    window.notraRevealAnchor = function(anchor) {
        const target = document.getElementById(anchor);
        if (!target) return;
        for (let section = target.closest('details.notra-heading-section');
             section;
             section = section.parentElement.closest('details.notra-heading-section')) {
            section.open = true;
        }
        target.scrollIntoView({ block: 'start', inline: 'nearest' });
    };
    document.addEventListener('click', function(event) {
        const link = event.target.closest('a[href^="#"]');
        if (!link) return;
        let anchor;
        try {
            anchor = decodeURIComponent(link.getAttribute('href').slice(1));
        } catch (_) {
            return;
        }
        if (!document.getElementById(anchor)) return;
        event.preventDefault();
        window.notraRevealAnchor(anchor);
    });
    """

    /// Passes only validated task-checkbox state changes from the generated document to Swift.
    private static let taskCheckboxScript = """
    document.addEventListener('change', function(event) {
        const checkbox = event.target;
        if (!(checkbox instanceof HTMLInputElement)) return;
        if (!checkbox.matches('input.task-checkbox[data-notra-task-line][data-notra-task-column][data-notra-task-state]')) return;
        const line = Number(checkbox.dataset.notraTaskLine);
        const column = Number(checkbox.dataset.notraTaskColumn);
        const wasChecked = checkbox.dataset.notraTaskState === 'checked';
        if (!Number.isInteger(line) || line < 1 || !Number.isInteger(column) || column < 1) return;
        window.webkit.messageHandlers.notraTaskToggle.postMessage({
            line: line,
            column: column,
            wasChecked: wasChecked,
            isChecked: checkbox.checked
        });
        checkbox.dataset.notraTaskState = checkbox.checked ? 'checked' : 'unchecked';
    });
    """

    func update(document: MarkdownHTMLDocument, in webView: WKWebView) {
        assetHandler.update(document.assets)
        let previousHTML = renderedHTML
        guard previousHTML != document.html else {
            return
        }
        renderedHTML = document.html
        documentGeneration += 1
        let generation = documentGeneration
        guard previousHTML != nil else {
            pendingPreviewState = nil
            webView.loadHTMLString(document.html, baseURL: nil)
            return
        }

        if pendingPreviewState != nil {
            webView.loadHTMLString(document.html, baseURL: nil)
            return
        }

        let captureScript = """
        return {
            scrollOffset: window.scrollY,
            collapsedHeadingAnchors: Array.from(document.querySelectorAll('details.notra-heading-section:not([open])'))
                .map(section => section.getAttribute('data-notra-heading-anchor'))
                .filter(anchor => typeof anchor === 'string')
        };
        """
        Task { [weak self, weak webView] in
            guard let self, let webView else { return }
            let value = try? await webView.callAsyncJavaScript(
                captureScript,
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            guard generation == documentGeneration else { return }
            if let value {
                pendingPreviewState = Self.previewState(from: value)
            }
            webView.loadHTMLString(document.html, baseURL: nil)
        }
    }

    private static func previewState(from value: Any) -> PreviewState? {
        guard let dictionary = value as? [String: Any],
              let offset = (dictionary["scrollOffset"] as? NSNumber)?.doubleValue,
              offset.isFinite,
              let anchors = dictionary["collapsedHeadingAnchors"] as? [String]
        else {
            return nil
        }
        return PreviewState(scrollOffset: offset, collapsedHeadingAnchors: anchors)
    }

    func cancelPendingReadiness() {
        documentGeneration += 1
        pendingPreviewState = nil
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation?) {
        let generation = documentGeneration
        Task { [weak self, weak webView] in
            guard let self, let webView, generation == documentGeneration else { return }
            if let state = pendingPreviewState {
                do {
                    _ = try await webView.callAsyncJavaScript(
                        """
                        const sections = Array.from(document.querySelectorAll('details.notra-heading-section'));
                        for (const anchor of anchors) {
                            const section = sections
                                .find(candidate => candidate.getAttribute('data-notra-heading-anchor') === anchor);
                            if (section) section.open = false;
                        }
                        return true;
                        """,
                        arguments: ["anchors": state.collapsedHeadingAnchors],
                        in: nil,
                        contentWorld: .page
                    )
                } catch {
                    _ = try? await webView.callAsyncJavaScript(
                        "document.querySelectorAll('details.notra-heading-section').forEach(section => section.open = true);",
                        arguments: [:],
                        in: nil,
                        contentWorld: .page
                    )
                    guard generation == documentGeneration else { return }
                    pendingPreviewState = nil
                }
                guard generation == documentGeneration else { return }
            }
            _ = try? await webView.callAsyncJavaScript(
                "await window.notraMermaidReady; return true;",
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            guard generation == documentGeneration, let state = pendingPreviewState else { return }
            do {
                _ = try await webView.callAsyncJavaScript(
                    "window.scrollTo(0, offset); return true;",
                    arguments: ["offset": state.scrollOffset],
                    in: nil,
                    contentWorld: .page
                )
            } catch {
                // The loaded document remains usable if scroll restoration fails.
            }
            guard generation == documentGeneration else { return }
            pendingPreviewState = nil
        }
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.taskToggleMessageName,
              let body = message.body as? [String: Any],
              let line = body["line"] as? Int,
              let column = body["column"] as? Int,
              let wasChecked = body["wasChecked"] as? Bool,
              let isChecked = body["isChecked"] as? Bool,
              line > 0,
              column > 0
        else {
            return
        }

        let marker = MarkdownTaskMarker(
            line: line,
            column: column,
            state: wasChecked ? .checked : .unchecked
        )
        toggleTask(marker, isChecked ? .checked : .unchecked)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url
        else {
            decisionHandler(.allow)
            return
        }

        if let anchor = inDocumentAnchor(for: url) {
            scroll(to: anchor, in: webView)
            decisionHandler(.cancel)
            return
        }

        openURL(url)
        decisionHandler(.cancel)
    }

    private func inDocumentAnchor(for url: URL) -> String? {
        guard let fragment = url.fragment,
              !fragment.isEmpty,
              url.scheme == nil || url.absoluteString.hasPrefix("about:blank#")
        else {
            return nil
        }

        return fragment.removingPercentEncoding ?? fragment
    }

    func scroll(to anchor: String, in webView: WKWebView) {
        Task { [weak webView] in
            guard let webView else { return }
            _ = try? await webView.callAsyncJavaScript(
                "window.notraRevealAnchor(anchor); return true;",
                arguments: ["anchor": anchor],
                in: nil,
                contentWorld: .page
            )
        }
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
