import Foundation
@testable import Notra
import Testing
import UniformTypeIdentifiers

struct AttachmentInspectorGroupsTests {
    @Test
    func `attachment groups preserve source order within interleaved kinds and link statuses`() {
        let firstLinkedImage = asset("first-linked.png", contentType: .png, isLinked: true)
        let secondLinkedImage = asset("second-linked.png", contentType: .png, isLinked: true)
        let firstUnlinkedImage = asset("first-unlinked.png", contentType: .png, isLinked: false)
        let secondUnlinkedImage = asset("second-unlinked.png", contentType: .png, isLinked: false)
        let firstLinkedFile = asset("first-linked.pdf", contentType: .pdf, isLinked: true)
        let secondLinkedFile = asset("second-linked.pdf", contentType: .pdf, isLinked: true)
        let firstUnlinkedFile = asset("first-unlinked.zip", contentType: .zip, isLinked: false)
        let secondUnlinkedFile = asset("second-unlinked.zip", contentType: .zip, isLinked: false)

        let groups = AttachmentInspectorGroups(attachments: [
            firstUnlinkedFile, firstLinkedImage, firstLinkedFile, firstUnlinkedImage,
            secondLinkedFile, secondUnlinkedImage, secondUnlinkedFile, secondLinkedImage
        ])

        #expect(groups.linkedImages == [firstLinkedImage, secondLinkedImage])
        #expect(groups.unlinkedImages == [firstUnlinkedImage, secondUnlinkedImage])
        #expect(groups.linkedFiles == [firstLinkedFile, secondLinkedFile])
        #expect(groups.unlinkedFiles == [firstUnlinkedFile, secondUnlinkedFile])
    }

    @Test
    func `empty attachments produce four empty groups`() {
        let groups = AttachmentInspectorGroups(attachments: [])

        #expect(groups.linkedImages.isEmpty)
        #expect(groups.unlinkedImages.isEmpty)
        #expect(groups.linkedFiles.isEmpty)
        #expect(groups.unlinkedFiles.isEmpty)
    }

    private func asset(_ filename: String, contentType: UTType, isLinked: Bool) -> TextBundleAsset {
        TextBundleAsset(
            url: URL.temporaryDirectory.appendingPathComponent(filename),
            contentType: contentType,
            byteCount: 1,
            isLinked: isLinked
        )
    }
}
