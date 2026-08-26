#if os(iOS)
import QuickLook
import SwiftUI

struct AttachmentPreviewItem: Identifiable {
    let url: URL

    var id: URL {
        url
    }
}

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
