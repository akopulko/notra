import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import PhotosUI
#endif

struct MarkdownAttachmentSelectionRequest: Equatable {
    static let empty = MarkdownAttachmentSelectionRequest(id: 0, url: nil)

    let id: Int
    let url: URL?
}

#if os(iOS)
struct ImagePickerPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var selection: PhotosPickerItem?
    let onSelection: (PhotosPickerItem) -> Void

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresented, selection: $selection, matching: .images)
            .onChange(of: selection) {
                guard let selection else {
                    return
                }
                onSelection(selection)
            }
    }
}
#endif

#if os(iOS) || os(macOS)
struct AttachmentFileImporterModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onSelection: (URL) -> Void
    let onError: (Error) -> Void

    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.item]) { result in
            switch result {
            case let .success(url):
                AppLog.info("Attachment file importer selected file; name=\(url.lastPathComponent)")
                onSelection(url)
            case let .failure(error):
                if error.isUserCancelled {
                    AppLog.debug("Attachment file importer cancelled")
                    return
                }
                AppLog.error("Attachment file importer failed: \(error.localizedDescription)")
                onError(error)
            }
        }
    }
}

private extension Error {
    var isUserCancelled: Bool {
        let error = self as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
    }
}
#endif

struct EmptyModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}
