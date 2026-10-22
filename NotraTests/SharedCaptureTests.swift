import Foundation
#if os(iOS)
import UIKit
import UniformTypeIdentifiers
#endif
@testable import Notra
import Testing

@MainActor
struct SharedCaptureTests {
#if os(iOS)
    @Test
    func composerAllowsRetypingAfterClearingSharedText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SharedCaptureStore(rootURL: root)
        let draft = try store.createDraftDirectory()
        let model = ShareComposerModel(store: store, draftDirectory: draft, context: nil)
        let item = NSExtensionItem()
        item.attributedContentText = NSAttributedString(string: "Selected text")
        await model.load(items: [item])

        #expect(model.canSave)
        #expect(model.isBodyEditable)

        model.body = ""
        #expect(!model.canSave)
        #expect(model.isBodyEditable)

        model.body = "Retyped text"
        #expect(model.canSave)
        #expect(model.isBodyEditable)
    }

    @Test
    func attributedTextCanBeLoadedWithoutAttachments() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let item = NSExtensionItem()
        item.attributedContentText = NSAttributedString(string: "Selected words")
        let capture = try await SharePayloadLoader.load(items: [item], draftDirectory: root)

        #expect(capture.body == "Selected words")
        #expect(capture.assets.isEmpty)
    }

    @Test
    func plainTextDataRepresentationLoadsAsSelectedText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) {
            completion in
            completion(Data("Selected from Safari".utf8), nil)
            return nil
        }
        let item = NSExtensionItem()
        item.attachments = [provider]
        let capture = try await SharePayloadLoader.load(items: [item], draftDirectory: root)

        #expect(capture.body == "Selected from Safari")
        #expect(capture.assets.isEmpty)
    }
#endif

    @Test
    func publishedDraftHasMarkerAndAtomicInboxEntry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SharedCaptureStore(rootURL: root)
        let draft = try store.createDraftDirectory()
        let repository = TextBundleNoteRepository(rootURL: draft)
        let note = try repository.createNote(initialMarkdown: "Captured body")

        let captureID = try store.publish(draftDirectory: draft, noteURL: note.url)
        let destination = root.appendingPathComponent(captureID.uuidString, isDirectory: true)
        let loaded = try TextBundleNoteRepository(rootURL: destination).loadNote(
            at: destination.appendingPathComponent("\(captureID.uuidString).textbundle")
        )
        let metadata = try JSONDecoder().decode(
            TextBundleInfo.self,
            from: Data(contentsOf: loaded.url.appendingPathComponent("info.json"))
        )

        #expect(loaded.markdown == "Captured body")
        #expect(metadata.notra.shareCaptureID == captureID)
        #expect(!FileManager.default.fileExists(atPath: draft.path(percentEncoded: false)))
    }
    @Test
    func importerPublishesCaptureAndRecognizesCompletedPublication() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("ShareInbox", isDirectory: true)
        let destinationRoot = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let store = SharedCaptureStore(rootURL: inbox)
        let draft = try store.createDraftDirectory()
        let draftRepository = TextBundleNoteRepository(rootURL: draft)
        let draftNote = try draftRepository.createNote(initialMarkdown: "Captured body")
        let captureID = try store.publish(draftDirectory: draft, noteURL: draftNote.url)
        let captureURL = inbox.appendingPathComponent(captureID.uuidString, isDirectory: true)
        let retainedCopy = root.appendingPathComponent("retained-capture", isDirectory: true)
        try FileManager.default.copyItem(at: captureURL, to: retainedCopy)
        let destination = TextBundleNoteRepository(rootURL: destinationRoot)
        let importer = SharedCaptureImporter(inboxURL: inbox, destination: destination)

        let firstDrain = await importer.drain()
        let imported = try #require(firstDrain.notes.first)
        #expect(imported.markdown == "Captured body")
        #expect(!FileManager.default.fileExists(atPath: captureURL.path(percentEncoded: false)))

        var edited = imported
        edited.markdown = "Edited after filing"
        try destination.save(edited)
        try FileManager.default.copyItem(at: retainedCopy, to: captureURL)
        let secondDrain = await importer.drain()
        #expect(secondDrain.notes.count == 1)
        #expect(try destination.loadNote(at: imported.url).markdown == "Edited after filing")
    }

    @Test
    func concurrentDrainsThroughSharedImporterFileCaptureOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("ShareInbox", isDirectory: true)
        let destinationRoot = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let store = SharedCaptureStore(rootURL: inbox)
        let draft = try store.createDraftDirectory()
        let draftRepository = TextBundleNoteRepository(rootURL: draft)
        let draftNote = try draftRepository.createNote(initialMarkdown: "Captured body")
        _ = try store.publish(draftDirectory: draft, noteURL: draftNote.url)
        let destination = TextBundleNoteRepository(rootURL: destinationRoot)

        async let first = SharedCaptureImporter.shared.drain(inboxURL: inbox, destination: destination)
        async let second = SharedCaptureImporter.shared.drain(inboxURL: inbox, destination: destination)
        let results = await (first, second)

        #expect(results.0.errors.isEmpty)
        #expect(results.1.errors.isEmpty)
        #expect(results.0.notes.count + results.1.notes.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: inbox.path(percentEncoded: false)).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: destinationRoot.path(percentEncoded: false)).count == 1)
    }
}
