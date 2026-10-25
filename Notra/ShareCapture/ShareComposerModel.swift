#if os(iOS)
import Foundation
import Observation
import UIKit

@MainActor @Observable
final class ShareComposerModel {
    enum State {
        case loading, ready, saving, error(String), completed, cancelled

        var allowsBodyEditing: Bool {
            switch self {
            case .ready, .error: true
            case .loading, .saving, .completed, .cancelled: false
            }
        }
    }

    private(set) var state: State = .loading
    var body = ""
    private(set) var assets: [ImportedTextBundleAsset] = []
    private(set) var thumbnails: [CGImage] = []
    private let store: SharedCaptureStore
    private let draftDirectory: URL
    private weak var context: NSExtensionContext?
    private var noteURL: URL?
    private var published = false

    init(store: SharedCaptureStore, draftDirectory: URL, context: NSExtensionContext?) {
        self.store = store
        self.draftDirectory = draftDirectory
        self.context = context
    }

    func load(items: [NSExtensionItem]) async {
        do {
            let capture = try await SharePayloadLoader.load(items: items, draftDirectory: draftDirectory)
            let thumbnails = capture.assets.compactMap {
                ImageThumbnailDecoder.decode(from: $0.url, maximumPixelSize: 256)
            }
            guard thumbnails.count == capture.assets.count else {
                throw SharePayloadLoader.Failure.loadFailed
            }
            noteURL = capture.noteURL
            body = capture.body
            assets = capture.assets
            self.thumbnails = thumbnails
            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    var canSave: Bool {
        guard case .ready = state else { return false }
        return !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !assets.isEmpty
    }

    var isBodyEditable: Bool {
        state.allowsBodyEditing
    }

    func save() {
        guard canSave, !published, let noteURL else { return }
        state = .saving
        let repository = TextBundleNoteRepository(rootURL: draftDirectory)
        let body = body
        let assets = assets
        let store = store
        let draftDirectory = draftDirectory
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let references = assets.enumerated().map { index, asset in
                    "![image-\(index + 1)](\(asset.source))"
                }
                let blocks = [body] + references
                let content = blocks.filter { !$0.isEmpty }.joined(separator: "\n\n")
                var note = try repository.loadNote(at: noteURL)
                note.markdown = content
                try await repository.save(note)
                try Task.checkCancellation()
                _ = try store.publish(draftDirectory: draftDirectory, noteURL: noteURL)
                await MainActor.run {
                    guard let self else { return }
                    self.published = true
                    self.state = .completed
                    self.context?.completeRequest(returningItems: nil)
                }
            } catch {
                await MainActor.run { self?.state = .error(String(localized: .shareCaptureSaveFailed)) }
            }
        }
    }

    func cancel() {
        guard case .saving = state else {
            try? store.discard(draftDirectory: draftDirectory)
            state = .cancelled
            context?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
            return
        }
    }
}

#endif
