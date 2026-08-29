import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A shareable PDF file backed by a temporary exported URL.
struct NotePDFShareItem: Equatable, Sendable, Transferable {
    let fileURL: URL
    let suggestedFilename: String
    let includedImageURLs: Set<URL>

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { item in
            SentTransferredFile(item.fileURL)
        }
    }
}
