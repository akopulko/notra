import Foundation
import UniformTypeIdentifiers

/// Describes one asset stored below a TextBundle's assets directory.
struct TextBundleAsset: Equatable, Identifiable, Sendable {
    /// Canonical asset URL used as the stable list identity.
    let url: URL
    /// MIME/UTType used to choose image versus generic-file presentation.
    let contentType: UTType?
    /// Whether the current Markdown body links to this asset.
    var isLinked: Bool

    init(url: URL, contentType: UTType?, isLinked: Bool) {
        self.url = url.notraCanonicalFileURL
        self.contentType = contentType
        self.isLinked = isLinked
    }

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

/// Separates image assets from attachments that need a generic file treatment.
enum TextBundleAssetKind: Equatable, Sendable {
    case image
    case attachment

    nonisolated init(contentType: UTType?, filename: String) {
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

/// Carries an imported asset's stored URL and Markdown link label back to the editor.
struct ImportedTextBundleAsset: Equatable, Sendable {
    /// Destination URL after the asset has been copied or encoded.
    let url: URL
    /// Relative Markdown source stored in the note body.
    let source: String
    /// Presentation kind selected from the imported content type.
    let kind: TextBundleAssetKind
    /// Final filename written below the bundle's assets directory.
    let filename: String

    init(url: URL, source: String, kind: TextBundleAssetKind, filename: String) {
        self.url = url.notraCanonicalFileURL
        self.source = source
        self.kind = kind
        self.filename = filename
    }
}

extension String {
    var percentEncodedMarkdownPathComponent: String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
