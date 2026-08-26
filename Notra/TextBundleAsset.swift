import Foundation
import UniformTypeIdentifiers

struct TextBundleAsset: Equatable, Identifiable, Sendable {
    let url: URL
    let contentType: UTType?
    var isLinked: Bool

    var id: URL {
        url
    }

    var filename: String {
        url.lastPathComponent
    }

    var kind: TextBundleAssetKind {
        TextBundleAssetKind(contentType: contentType, filename: filename)
    }

    var markdownSource: String {
        "\(TextBundleNoteRepository.assetsFolder)/\(filename.percentEncodedMarkdownPathComponent)"
    }
}

enum TextBundleAssetKind: Equatable, Sendable {
    case image
    case attachment

    init(contentType: UTType?, filename: String) {
        if contentType?.conforms(to: .image) == true {
            self = .image
            return
        }

        if let type = UTType(filenameExtension: URL(fileURLWithPath: filename).pathExtension), type.conforms(to: .image) {
            self = .image
            return
        }

        self = .attachment
    }

    var isImage: Bool {
        self == .image
    }
}

struct ImportedTextBundleAsset: Equatable, Sendable {
    let url: URL
    let source: String
    let kind: TextBundleAssetKind
    let filename: String
}

extension String {
    var percentEncodedMarkdownPathComponent: String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
