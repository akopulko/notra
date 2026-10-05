import Foundation
import UniformTypeIdentifiers

extension TextBundleNoteRepository {
    /// Summarizes only linked assets so unused files do not produce row-level attachment indicators.
    private nonisolated func attachmentSummary(for noteURL: URL, markdown: String) throws -> NoteAttachmentSummary {
        try attachmentSummary(
            for: noteURL,
            analysis: MarkdownDocumentAnalysis.analyse(markdown: markdown)
        )
    }

    nonisolated func attachmentSummary(
        for noteURL: URL,
        analysis: MarkdownDocumentAnalysis
    ) throws -> NoteAttachmentSummary {
        let assetBaseURL = noteURL.appendingPathComponent(Self.assetsFolder, isDirectory: true)
        let linkedURLs = MarkdownAttachmentReferences.linkedURLs(in: analysis, assetBaseURL: assetBaseURL)
        guard !linkedURLs.isEmpty else {
            return .empty
        }

        var linkedImageURLs: [URL] = []
        var hasLinkedNonImageAttachment = false
        for assetURL in try assetURLs(in: noteURL) {
            try Task.checkCancellation()
            let standardizedURL = assetURL.notraCanonicalFileURL
            guard linkedURLs.contains(standardizedURL) else {
                continue
            }

            let contentType = try assetURL.resourceValues(forKeys: [.contentTypeKey]).contentType
                ?? UTType(filenameExtension: assetURL.pathExtension)
            switch TextBundleAssetKind(contentType: contentType, filename: assetURL.lastPathComponent) {
            case .image:
                linkedImageURLs.append(standardizedURL)
            case .attachment:
                hasLinkedNonImageAttachment = true
            }
        }

        return NoteAttachmentSummary(
            linkedImageURLs: linkedImageURLs,
            hasLinkedNonImageAttachment: hasLinkedNonImageAttachment
        )
    }

    /// Uses the Markdown file timestamp first, falling back to the bundle timestamp for old bundles.
    nonisolated func modifiedDate(of bundleURL: URL) throws -> Date {
        let textURL = bundleURL.appendingPathComponent(Self.textFilename)
        let textValues = try textURL.resourceValues(forKeys: [.contentModificationDateKey])
        if let modifiedAt = textValues.contentModificationDate {
            return modifiedAt
        }
        let bundleValues = try bundleURL.resourceValues(forKeys: [.contentModificationDateKey])
        return bundleValues.contentModificationDate ?? .distantPast
    }

    /// Reads the required UTF-8 Markdown member of a TextBundle.
    nonisolated func markdownContent(in bundleURL: URL) throws -> String {
        let textURL = bundleURL.appendingPathComponent(Self.textFilename)
        return try String(contentsOf: textURL, encoding: .utf8)
    }

    /// Builds a short plain-text preview while skipping table structure and Markdown markers.
    nonisolated static func preview(for markdown: String) -> NotePreview {
        let lines = previewSourceLines(from: markdown)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let previewLines = lines
            .prefix(3)
            .map { line in
                NotePreview.Line(text: plainText(fromMarkdownLine: line), isHeading: isMarkdownHeading(line))
            }
            .filter { !$0.text.isEmpty }

        guard !previewLines.isEmpty else {
            return NotePreview(text: NoteSummary.emptyPreviewText, firstLineIsHeading: false)
        }

        return NotePreview(
            text: previewLines.map(\.text).joined(separator: "\n"),
            firstLineIsHeading: previewLines.first?.isHeading ?? false
        )
    }

    /// Removes complete GFM table blocks before choosing the first preview lines.
    private nonisolated static func previewSourceLines(from markdown: String) -> [String] {
        let lines = markdown.components(separatedBy: .newlines)
        var previewLines: [String] = []
        var index = 0

        while index < lines.count {
            guard isTableHeader(lines[index]),
                  index + 1 < lines.count,
                  let columnCount = tableColumnCount(in: lines[index + 1]),
                  tableCellCount(in: lines[index]) == columnCount
            else {
                previewLines.append(lines[index])
                index += 1
                continue
            }

            index += 2
            while index < lines.count, isTableRow(lines[index]) {
                index += 1
            }
        }

        return previewLines
    }

    private nonisolated static func isTableHeader(_ line: String) -> Bool {
        line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private nonisolated static func isTableRow(_ line: String) -> Bool {
        line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private nonisolated static func tableColumnCount(in delimiter: String) -> Int? {
        let cells = tableCells(in: delimiter)
        guard !cells.isEmpty,
              cells.allSatisfy({
                  $0.trimmingCharacters(in: .whitespaces)
                      .range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
              })
        else {
            return nil
        }

        return cells.count
    }

    private nonisolated static func tableCellCount(in row: String) -> Int {
        tableCells(in: row).count
    }

    private nonisolated static func tableCells(in line: String) -> [Substring] {
        var row = line[...]
        if row.first == "|" {
            row.removeFirst()
        }
        if row.last == "|" {
            row.removeLast()
        }
        return row.split(separator: "|", omittingEmptySubsequences: false)
    }

    private nonisolated static func plainText(fromMarkdownLine line: String) -> String {
        line
            .replacingOccurrences(
                of: #"^\s{0,3}#{1,6}\s+"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s+#{1,6}\s*$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"^\s{0,3}>\s?"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"^\s*([-*+]|\d+[.)])\s+"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"^\s*\[[ xX]\]\s+"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"!\[([^\]]*)\]\([^)]+\)"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\[([^\]]+)\]\([^)]+\)"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"[*_`~]+"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func isMarkdownHeading(_ line: String) -> Bool {
        line.range(
            of: #"^\s{0,3}#{1,6}(\s|$)"#,
            options: .regularExpression
        ) != nil
    }
}

/// The parsed first-line and attachment summary used to build a sidebar note summary.
struct NotePreview: Equatable {
    struct Line: Equatable {
        let text: String
        let isHeading: Bool
    }

    let text: String
    let firstLineIsHeading: Bool
}
