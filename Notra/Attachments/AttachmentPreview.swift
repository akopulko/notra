#if os(iOS)
import QuickLook
import SwiftUI

/// Identifies the local file currently handed to Quick Look for preview.
struct AttachmentPreviewItem: Identifiable {
    let url: URL

    var id: URL {
        url
    }
}

/// Bridges Quick Look's preview controller into the iOS SwiftUI attachment flow.
struct AttachmentPreviewController: UIViewControllerRepresentable {
    let item: AttachmentPreviewItem

    func makeCoordinator() -> Coordinator {
        Coordinator(item: item)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_: QLPreviewController, context: Context) {
        context.coordinator.item = item
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var item: AttachmentPreviewItem

        init(item: AttachmentPreviewItem) {
            self.item = item
        }

        func numberOfPreviewItems(in _: QLPreviewController) -> Int {
            1
        }

        func previewController(
            _: QLPreviewController,
            previewItemAt _: Int
        ) -> QLPreviewItem {
            item.url as NSURL
        }
    }
}
#endif
