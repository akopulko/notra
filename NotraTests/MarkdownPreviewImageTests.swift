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
}
