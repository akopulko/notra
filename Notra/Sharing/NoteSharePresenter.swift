import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Provides platform-specific presentation hooks for sharing an already-generated file.
@MainActor
final class NoteSharePresenter {
    #if os(macOS)
    private weak var sourceView: NSView?
    private var picker: NSSharingServicePicker?

    func setSourceView(_ view: NSView) {
        sourceView = view
    }

    func clearSourceView(_ view: NSView) {
        guard sourceView === view else {
            return
        }
        sourceView = nil
    }
    #endif

    func present(fileURL: URL) -> Bool {
        #if os(iOS)
        guard let presenter = activeViewController() else {
            return false
        }

        let activityController = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        if let popover = activityController.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = presenter.view.bounds
        }
        presenter.present(activityController, animated: true)
        return true
        #else
        guard let sourceView, sourceView.window != nil else {
            AppLog.error("Cannot present share picker: share toolbar anchor is unavailable")
            return false
        }

        sourceView.layoutSubtreeIfNeeded()
        guard sourceView.bounds.width > 0, sourceView.bounds.height > 0 else {
            AppLog.error("Cannot present share picker: share toolbar anchor is unavailable")
            return false
        }

        let picker = NSSharingServicePicker(items: [fileURL])
        self.picker = picker
        picker.show(
            relativeTo: sourceView.bounds,
            of: sourceView,
            preferredEdge: .minY
        )
        return true
        #endif
    }

    #if os(iOS)
    private func activeViewController() -> UIViewController? {
        let rootViewController = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        return presentedViewController(from: rootViewController)
    }

    private func presentedViewController(from viewController: UIViewController?) -> UIViewController? {
        guard let viewController else {
            return nil
        }

        if let presentedController = viewController.presentedViewController {
            return presentedViewController(from: presentedController)
        }
        if let navigationController = viewController as? UINavigationController {
            return presentedViewController(from: navigationController.visibleViewController)
        }
        if let tabBarController = viewController as? UITabBarController {
            return presentedViewController(from: tabBarController.selectedViewController)
        }
        return viewController
    }
    #endif
}

#if os(macOS)
struct NoteShareAnchorView: NSViewRepresentable {
    let presenter: NoteSharePresenter

    func makeCoordinator() -> Coordinator {
        Coordinator(presenter: presenter)
    }

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        presenter.setSourceView(view)
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        presenter.setSourceView(view)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.presenter.clearSourceView(view)
    }

    final class Coordinator {
        let presenter: NoteSharePresenter

        init(presenter: NoteSharePresenter) {
            self.presenter = presenter
        }
    }
}
#endif
