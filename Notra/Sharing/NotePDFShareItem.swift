import CoreTransferable
import Foundation
import UniformTypeIdentifiers

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
