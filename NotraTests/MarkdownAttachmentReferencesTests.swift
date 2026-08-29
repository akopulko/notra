import Foundation
@testable import Notra
import Testing

@MainActor
/// Protects attachment-link resolution and removal across Markdown edge cases.
struct MarkdownAttachmentReferencesTests {
    @Test func findsOnlyLocalAssetReferences() {
        let assetBaseURL = URL(fileURLWithPath: "/tmp/example.textbundle/assets", isDirectory: true)
        let markdown = """
        ![Local](assets/local.jpg)
        [Ordinary link](assets/linked.pdf)
        `![Inline code](assets/code.jpg)`

        ```markdown
        ![Fenced code](assets/fenced.jpg)
        ```

        ![Remote](https://example.com/remote.jpg)
        """

        let linkedURLs = MarkdownAttachmentReferences.linkedURLs(
            in: markdown,
            assetBaseURL: assetBaseURL
        )

        #expect(linkedURLs == [
            assetBaseURL.appendingPathComponent("linked.pdf"),
            assetBaseURL.appendingPathComponent("local.jpg")
        ])
    }

    @Test func removesAllMatchingReferencesWithoutDamagingUnicode() {
        let assetBaseURL = URL(fileURLWithPath: "/tmp/example.textbundle/assets", isDirectory: true)
        let markdown = """
        Before 🚀
        ![First](assets/image.jpg)
        Between
        ![Second](assets/image.jpg)
        After
        """

        let result = MarkdownAttachmentReferences.removingReferences(
            to: assetBaseURL.appendingPathComponent("image.jpg"),
            from: markdown,
            assetBaseURL: assetBaseURL
        )

        #expect(result == """
        Before 🚀
        
        Between
        
        After
        """)
    }

    @Test func removesMatchingMarkdownLinksWithoutDamagingUnicode() {
        let assetBaseURL = URL(fileURLWithPath: "/tmp/example.textbundle/assets", isDirectory: true)
        let markdown = "Before 🚀 [Report](assets/report.pdf) After"

        let result = MarkdownAttachmentReferences.removingReferences(
            to: assetBaseURL.appendingPathComponent("report.pdf"),
            from: markdown,
            assetBaseURL: assetBaseURL
        )

        #expect(result == "Before 🚀  After")
    }

    @Test func resolvesRelativeAndPercentEncodedAssetReferences() {
        let assetBaseURL = URL(fileURLWithPath: "/tmp/example.textbundle/assets", isDirectory: true)
        let markdown = "![Relative](image.jpg) ![Encoded](assets/image%2Ejpg)"

        let linkedURLs = MarkdownAttachmentReferences.linkedURLs(
            in: markdown,
            assetBaseURL: assetBaseURL
        )

        #expect(linkedURLs == [assetBaseURL.appendingPathComponent("image.jpg")])
    }
}
