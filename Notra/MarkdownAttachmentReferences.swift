import Foundation
import Markdown

/// Finds and removes Markdown links that resolve to files in a TextBundle's assets directory.
enum MarkdownAttachmentReferences {
    struct Reference: Equatable {
        let source: String?
        let range: SourceRange?
    }

    nonisolated static func linkedURLs(in markdown: String, assetBaseURL: URL) -> Set<URL> {
        linkedURLs(
            in: MarkdownDocumentAnalysis.analyse(markdown: markdown),
            assetBaseURL: assetBaseURL
        )
    }

    nonisolated static func linkedURLs(
        in analysis: MarkdownDocumentAnalysis,
        assetBaseURL: URL
    ) -> Set<URL> {
        Set(analysis.attachmentSources.compactMap { source in
            guard let resolvedURL = resolve(source, assetBaseURL: assetBaseURL),
                  resolvedURL.isFileURL
            else {
                return nil
            }
            return resolvedURL
        })
    }

    static func removingReferences(
        to targetURL: URL,
        from markdown: String,
        assetBaseURL: URL
    ) -> String {
        let targetURL = targetURL.notraCanonicalFileURL
        let ranges = references(in: markdown).compactMap { reference -> Range<String.Index>? in
            guard let sourceURL = resolve(reference.source, assetBaseURL: assetBaseURL),
                  sourceURL == targetURL,
                  let range = reference.range
            else {
                return nil
            }

            return stringRange(for: range, in: markdown)
        }

        var result = markdown
        for range in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            result.removeSubrange(range)
        }
        return result
    }

    nonisolated static func resolve(_ source: String?, assetBaseURL: URL?) -> URL? {
        guard let source, !source.isEmpty else {
            return nil
        }

        if let absoluteURL = URL(string: source), absoluteURL.scheme != nil {
            if absoluteURL.isFileURL {
                guard let assetBaseURL else {
                    return nil
                }

                let baseURL = assetBaseURL.notraCanonicalFileURL
                let resolvedURL = absoluteURL.notraCanonicalFileURL
                guard resolvedURL.path.hasPrefix("\(baseURL.path)/") else {
                    return nil
                }
                return resolvedURL
            }
            return absoluteURL
        }

        guard let assetBaseURL,
              let decodedSource = source.removingPercentEncoding
        else {
            return nil
        }

        let components = decodedSource.split(separator: "/", omittingEmptySubsequences: false)
        guard !decodedSource.hasPrefix("/"),
              !components.contains(where: { $0 == "." || $0 == ".." }),
              !components.contains(where: { $0.isEmpty })
        else {
            return nil
        }

        let relativeComponents: [Substring] = if components.first == Substring(TextBundleNoteRepository.assetsFolder) {
            Array(components.dropFirst())
        } else {
            Array(components)
        }
        guard !relativeComponents.isEmpty else {
            return nil
        }

        let baseURL = assetBaseURL.notraCanonicalFileURL
        let resolvedURL = relativeComponents.reduce(baseURL) { url, component in
            url.appendingPathComponent(String(component))
        }.notraCanonicalFileURL
        let basePath = baseURL.path
        let resolvedPath = resolvedURL.path

        guard resolvedPath == basePath || resolvedPath.hasPrefix("\(basePath)/") else {
            return nil
        }

        return resolvedURL
    }
}

private extension MarkdownAttachmentReferences {
    nonisolated static func references(in markdown: String) -> [Reference] {
        let document = Document(parsing: markdown)
        return references(in: document)
    }

    nonisolated static func references(in markup: any Markup) -> [Reference] {
        let ownReferences: [Reference] = if let image = markup as? Markdown.Image {
            [Reference(source: image.source, range: image.range)]
        } else if let link = markup as? Markdown.Link {
            [Reference(source: link.destination, range: link.range)]
        } else {
            []
        }

        return ownReferences + markup.children.flatMap { references(in: $0) }
    }

    static func stringRange(
        for sourceRange: SourceRange,
        in string: String
    ) -> Range<String.Index>? {
        guard let lowerOffset = utf8Offset(for: sourceRange.lowerBound, in: string),
              let upperOffset = utf8Offset(for: sourceRange.upperBound, in: string),
              lowerOffset <= upperOffset,
              let lowerIndex = stringIndex(forUTF8Offset: lowerOffset, in: string),
              let upperIndex = stringIndex(forUTF8Offset: upperOffset, in: string)
        else {
            return nil
        }

        return lowerIndex..<upperIndex
    }

    static func stringIndex(forUTF8Offset offset: Int, in string: String) -> String.Index? {
        guard offset <= string.utf8.count else {
            return nil
        }

        let utf8Index = string.utf8.index(string.utf8.startIndex, offsetBy: offset)
        return String.Index(utf8Index, within: string)
    }

    static func utf8Offset(for location: SourceLocation, in string: String) -> Int? {
        guard location.line > 0, location.column > 0 else {
            return nil
        }

        var line = 1
        var lineStart = 0
        for (offset, byte) in string.utf8.enumerated() {
            if line == location.line {
                let result = lineStart + location.column - 1
                return result <= string.utf8.count ? result : nil
            }
            if byte == 0x0A {
                line += 1
                lineStart = offset + 1
            }
        }

        guard line == location.line else {
            return nil
        }
        let result = lineStart + location.column - 1
        return result <= string.utf8.count ? result : nil
    }
}
