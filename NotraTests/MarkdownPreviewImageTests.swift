import Foundation
@testable import Notra
import Testing
import WebKit

@MainActor
struct MarkdownPreviewImageTests {
    @Test func attachedTextBundleImageLoadsInInitialPreviewDocument() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleURL = rootURL.appendingPathComponent("Preview.textbundle", isDirectory: true)
        let assetsURL = bundleURL.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let pngData = try #require(
            Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jvN8AAAAASUVORK5CYII=")
        )
        try pngData.write(to: assetsURL.appendingPathComponent("attached.png"))

        let parsed = SwiftMarkdownParser().parse("![Attached](assets/attached.png)")
        var renderer = MarkdownHTMLRenderer(
            style: .notra(previewFontName: AppearanceFont.defaultName),
            mode: .preview,
            context: MarkdownRenderContext(noteURL: bundleURL, assetBaseURL: assetsURL)
        )
        let document = renderer.render(parsed)
        #expect(document.assets.count == 1)

        let coordinator = Coordinator(openURL: { _ in }, toggleTask: { _, _ in })
        let webView = coordinator.makeWebView()
        coordinator.update(document: document, in: webView)

        var imageWidth = 0
        for _ in 0..<100 {
            let result = try await webView.callAsyncJavaScript(
                "const image = document.querySelector('img'); return image ? image.naturalWidth : 0;",
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            imageWidth = result as? Int ?? 0
            if imageWidth > 0 {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(imageWidth == 1)
        coordinator.cancelPendingReadiness()
        webView.stopLoading()
    }
    @Test
    func mixedMarkdownRendersAcrossWebKitBlockTypes() async throws {
        let parsed = SwiftMarkdownParser().parse(MarkdownRenderingFixture.mixedDocument)
        var renderer = MarkdownHTMLRenderer(
            style: .notra(previewFontName: AppearanceFont.defaultName),
            mode: .preview,
            context: .empty
        )
        let document = renderer.render(parsed)
        let coordinator = Coordinator(openURL: { _ in }, toggleTask: { _, _ in })
        let webView = coordinator.makeWebView()
        defer {
            coordinator.cancelPendingReadiness()
            webView.stopLoading()
        }
        coordinator.update(document: document, in: webView)

        var hasLoadedPreview = false
        for _ in 0 ..< 100 {
            let readiness = try await webView.callAsyncJavaScript(
                "return document.readyState === 'complete' && Boolean(document.querySelector('h1'));",
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            hasLoadedPreview = readiness as? Bool == true
            if hasLoadedPreview {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(hasLoadedPreview)

        let result = try await webView.callAsyncJavaScript(
            """
            await Promise.race([
              window.notraMermaidReady,
              new Promise((_, reject) => setTimeout(() => reject(new Error('Timed out')), 30000))
            ]);
            const checkbox = document.querySelector('input.task-checkbox');
            const diagram = document.querySelector('.notra-mermaid');
            return JSON.stringify({
              heading: document.querySelector('h1')?.textContent.trim(),
              ordered: document.querySelector('ol > li')?.textContent.trim(),
              nested: document.querySelector('ol > li > ul > li')?.textContent.trim(),
              taskCount: document.querySelectorAll('input.task-checkbox').length,
              taskChecked: checkbox?.checked,
              taskText: checkbox?.parentElement?.textContent.trim(),
              quote: document.querySelector('blockquote')?.textContent.trim(),
              cells: Array.from(document.querySelectorAll('table th, table td'), cell => cell.textContent.trim()),
              diagramState: diagram?.dataset.notraMermaidState,
              diagramSVGCount: diagram?.querySelectorAll('svg').length,
              diagramText: diagram?.querySelector('svg')?.textContent.trim()
            });
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        let json = try #require(result as? String)
        let content = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])

        #expect(content["heading"] as? String == "Verification 👋")
        #expect(content["ordered"] as? String == "Ordered fixtureNested fixture")
        #expect(content["nested"] as? String == "Nested fixture")
        #expect(content["taskCount"] as? Int == 1)
        #expect(content["taskChecked"] as? Bool == false)
        #expect(content["taskText"] as? String == "Task fixture")
        #expect(content["quote"] as? String == "Quote fixture")
        #expect(content["cells"] as? [String] == ["Key", "Value", "Left fixture", "Right fixture"])
        #expect(content["diagramState"] as? String == "rendered")
        #expect(content["diagramSVGCount"] as? Int == 1)
        let diagramText = try #require(content["diagramText"] as? String)
        #expect(diagramText.contains("Start fixture"))
        #expect(diagramText.contains("End fixture"))
    }

}
