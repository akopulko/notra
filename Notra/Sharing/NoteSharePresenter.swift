import Foundation

#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
enum NoteSharePresenter {
    static func present(fileURL: URL) {
        #if os(iOS)
        guard let presenter = activeViewController() else {
            return
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
        #else
        guard let contentView = NSApplication.shared.keyWindow?.contentView else {
            return
        }

        let picker = NSSharingServicePicker(items: [fileURL])
        picker.show(
            relativeTo: contentView.bounds,
            of: contentView,
            preferredEdge: .minY
        )
        #endif
    }

    #if os(iOS)
    private static func activeViewController() -> UIViewController? {
        let rootViewController = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        return presentedViewController(from: rootViewController)
    }

    private static func presentedViewController(from viewController: UIViewController?) -> UIViewController? {
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
