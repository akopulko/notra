import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private var model: ShareComposerModel?

    override func viewDidLoad() {
        super.viewDidLoad()
        do {
            let store = try SharedCaptureStore.production()
            let draft = try store.createDraftDirectory()
            let model = ShareComposerModel(store: store, draftDirectory: draft, context: extensionContext)
            self.model = model
            let host = UIHostingController(rootView: ShareComposerView(model: model))
            addChild(host)
            view.addSubview(host.view)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: view.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            host.didMove(toParent: self)
            Task { await model.load(items: extensionContext?.inputItems as? [NSExtensionItem] ?? []) }
        } catch {
            extensionContext?.cancelRequest(withError: error)
        }
    }
}
