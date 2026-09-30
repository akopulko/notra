import Foundation
@testable import Notra
import Testing
import WebKit

@MainActor
struct MermaidRenderingTests {
    @Test func validInvalidAndFollowingDiagramsSettleInWebKit() async throws {
        let markdown = """
        ```mermaid
        flowchart TD
        A[DiagramStart] --> B[DiagramEnd]
        ```

        ```mermaid
        flowchart TD
        A[unterminated
        ```

        ```mermaid
        sequenceDiagram
        Alice->>Bob: SequenceEnd
        ```
        """
        let parsed = SwiftMarkdownParser().parse(markdown)
        var renderer = MarkdownHTMLRenderer(
            style: .notra(previewFontName: AppearanceFont.defaultName),
            mode: .preview,
            context: .empty
        )
        let document = renderer.render(parsed)
        let configuration = WKWebViewConfiguration()
        MarkdownMermaidRuntime.configure(configuration)
        let assets = MarkdownWebAssetHandler()
        assets.update(document.assets)
        configuration.setURLSchemeHandler(assets, forURLScheme: MarkdownWebAssetHandler.scheme)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let loader = NavigationLoader()
        webView.navigationDelegate = loader

        try await loader.load(document.html, in: webView)
        let value = try await webView.callAsyncJavaScript(
            """
            await Promise.race([
              window.notraMermaidReady,
              new Promise((_, reject) => setTimeout(() => reject(new Error('Timed out')), 30000))
            ]);
            return JSON.stringify(Array.from(document.querySelectorAll('.notra-mermaid')).map(section => ({
              state: section.dataset.notraMermaidState,
              sourceHidden: section.querySelector('.notra-mermaid-source').hidden,
              errorHidden: section.querySelector('.notra-mermaid-error').hidden,
              source: section.querySelector('.notra-mermaid-source').textContent,
              svgText: section.querySelector('svg')?.textContent || '',
              svgCount: section.querySelectorAll('svg').length,
              viewBox: section.querySelector('svg')?.getAttribute('viewBox') || null
            })));
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        let json = try #require(value as? String)
        let result = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])

        #expect(result.count == 3)
        #expect(result[0]["state"] as? String == "rendered")
        #expect(result[0]["sourceHidden"] as? Bool == true)
        #expect(result[0]["svgCount"] as? Int == 1)
        #expect(result[0]["viewBox"] is String)
        #expect(result[1]["state"] as? String == "error")
        #expect(result[1]["sourceHidden"] as? Bool == false)
        #expect(result[1]["errorHidden"] as? Bool == false)
        #expect((result[1]["source"] as? String)?.contains("A[unterminated") == true)
        #expect(result[2]["state"] as? String == "rendered")
        #expect(result[2]["svgCount"] as? Int == 1)
        #expect((result[2]["svgText"] as? String)?.contains("SequenceEnd") == true)
    }
    @Test func strictSanitizationAndResponsiveWidthHoldForUntrustedLabels() async throws {
        let links = (0..<24).map { index in
            "N\(index)[Node \(index) with a deliberately long label] --> N\(index + 1)"
        }.joined(separator: "\n")
        let markdown = """
        ```mermaid
        %%{init: {"securityLevel": "loose"}}%%
        flowchart LR
        A["<script>window.notraInjected = true</script>"] --> B
        ```

        ```mermaid
        flowchart LR
        \(links)
        ```
        """
        let parsed = SwiftMarkdownParser().parse(markdown)
        var renderer = MarkdownHTMLRenderer(
            style: .notra(previewFontName: AppearanceFont.defaultName),
            mode: .preview,
            context: .empty
        )
        let document = renderer.render(parsed)
        let configuration = WKWebViewConfiguration()
        MarkdownMermaidRuntime.configure(configuration)
        let assets = MarkdownWebAssetHandler()
        assets.update(document.assets)
        configuration.setURLSchemeHandler(assets, forURLScheme: MarkdownWebAssetHandler.scheme)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 700), configuration: configuration)
        let loader = NavigationLoader()
        webView.navigationDelegate = loader

        try await loader.load(document.html, in: webView)
        let value = try await webView.callAsyncJavaScript(
            """
            await Promise.race([
              window.notraMermaidReady,
              new Promise((_, reject) => setTimeout(() => reject(new Error('Timed out')), 30000))
            ]);
            const svgs = Array.from(document.querySelectorAll('.notra-mermaid svg'));
            const forbidden = svgs.some(svg => svg.querySelector('script, iframe, foreignObject, image') ||
              Array.from(svg.querySelectorAll('*')).some(element =>
                Array.from(element.attributes).some(attribute => attribute.name.toLowerCase().startsWith('on'))));
            return JSON.stringify({
              injected: window.notraInjected === true,
              forbidden,
              states: Array.from(document.querySelectorAll('.notra-mermaid')).map(section => section.dataset.notraMermaidState),
              svgWidths: svgs.map(svg => svg.getBoundingClientRect().width),
              svgHeights: svgs.map(svg => svg.getBoundingClientRect().height),
              contentWidth: document.body.clientWidth
            });
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        let json = try #require(value as? String)
        let result = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let states = try #require(result["states"] as? [String])
        let widths = try #require(result["svgWidths"] as? [Double])
        let contentWidth = try #require(result["contentWidth"] as? Double)
        let heights = try #require(result["svgHeights"] as? [Double])

        #expect(result["injected"] as? Bool == false)
        #expect(result["forbidden"] as? Bool == false)
        #expect(states == ["rendered", "rendered"])
        #expect(widths.allSatisfy { $0 > 0 && $0 <= contentWidth })
        #expect(heights.allSatisfy { $0 > 0 })
    }
}

@MainActor
private final class NavigationLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, any Error>?
    private var timeoutTask: Task<Void, Never>?

    func load(_ html: String, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task {
                try? await Task.sleep(for: .seconds(30))
                guard let continuation = self.continuation else { return }
                self.continuation = nil
                continuation.resume(throwing: URLError(.timedOut))
            }
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        timeoutTask?.cancel()
        continuation?.resume()
        continuation = nil
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: any Error) {
        timeoutTask?.cancel()
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
