#if os(iOS)
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

struct LoadedShareCapture: Sendable {
    let noteURL: URL
    let body: String
    let assets: [ImportedTextBundleAsset]
}

enum SharePayloadLoader {
    enum Failure: LocalizedError {
        case unsupportedContent
        case loadFailed
        case limitExceeded

        var errorDescription: String? {
            switch self {
            case .unsupportedContent: String(localized: .shareCaptureUnsupportedContent)
            case .loadFailed: String(localized: .shareCaptureLoadFailed)
            case .limitExceeded: String(localized: .shareCaptureLimitExceeded)
            }
        }
    }

    @MainActor
    static func load(items: [NSExtensionItem], draftDirectory: URL) async throws -> LoadedShareCapture {
        let repository = TextBundleNoteRepository(rootURL: draftDirectory)
        let note = try repository.createNote()
        let providers = items.flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty else { throw Failure.unsupportedContent }
        var accumulator = Accumulator()
        for provider in providers {
            try await append(
                provider,
                to: &accumulator,
                repository: repository,
                noteURL: note.url,
                draftDirectory: draftDirectory
            )
        }
        for item in items {
            if let text = item.attributedContentText?.string {
                let isDuplicate = accumulator.text.contains { $0 == text }
                if !isDuplicate {
                    accumulator.text.append(text)
                }
            }
        }
        let body = accumulator.text.joined(separator: "\n\n")
        guard body.utf8.count <= 1048576 else { throw Failure.limitExceeded }
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !accumulator.assets.isEmpty else {
            throw Failure.unsupportedContent
        }
        return LoadedShareCapture(noteURL: note.url, body: body, assets: accumulator.assets)
    }

    private struct Accumulator {
        var text: [String] = []
        var assets: [ImportedTextBundleAsset] = []
        var imageBytes = 0
        var urlCount = 0
    }

    @MainActor
    private static func append(
        _ provider: NSItemProvider,
        to accumulator: inout Accumulator,
        repository: TextBundleNoteRepository,
        noteURL: URL,
        draftDirectory: URL
    ) async throws {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            try await appendImage(
                provider,
                to: &accumulator,
                repository: repository,
                noteURL: noteURL,
                draftDirectory: draftDirectory
            )
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            let url = try await loadURL(from: provider)
            guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
                throw Failure.unsupportedContent
            }
            let block = "<\(url.absoluteString)>"
            guard !accumulator.text.contains(block) else { return }
            let isDuplicatePlainURL = accumulator.text.contains {
                $0.trimmingCharacters(in: .whitespacesAndNewlines) == url.absoluteString
            }
            if isDuplicatePlainURL {
                return
            }
            guard accumulator.urlCount < 10 else { throw Failure.limitExceeded }
            accumulator.urlCount += 1
            accumulator.text.append(block)
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            let text = try await loadText(from: provider)
            guard text.utf8.count <= 1024 * 1024 else { throw Failure.limitExceeded }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = webURL(from: trimmed) {
                let linkBlock = "<\(url.absoluteString)>"
                if !accumulator.text.contains(linkBlock) {
                    guard accumulator.urlCount < 10 else { throw Failure.limitExceeded }
                    accumulator.urlCount += 1
                    accumulator.text.append(linkBlock)
                }
            } else if !accumulator.text.contains(where: { $0 == text }) {
                accumulator.text.append(text)
            }
        } else {
            throw Failure.unsupportedContent
        }
    }

    @MainActor
    private static func appendImage(
        _ provider: NSItemProvider,
        to accumulator: inout Accumulator,
        repository: TextBundleNoteRepository,
        noteURL: URL,
        draftDirectory: URL
    ) async throws {
        guard accumulator.assets.count < 10 else { throw Failure.limitExceeded }
        let sourceURL = try await loadImageFile(from: provider, draftDirectory: draftDirectory)
        let byteCount = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        accumulator.imageBytes += byteCount
        guard accumulator.imageBytes <= 100 * 1048576 else { throw Failure.limitExceeded }
        let asset = try repository.importImage(
            from: sourceURL,
            originalFilename: "image-\(accumulator.assets.count + 1)",
            into: noteURL,
            maximumPixelSize: 4096,
            jpegQuality: 0.9
        )
        accumulator.assets.append(asset)
        try? FileManager.default.removeItem(at: sourceURL)
    }

    private static func webURL(from value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil
        else {
            return nil
        }
        return url
    }

    private static func loadImageFile(from provider: NSItemProvider, draftDirectory: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { source, error in
                guard let source, error == nil else {
                    continuation.resume(throwing: Failure.loadFailed)
                    return
                }
                let destination = draftDirectory.appendingPathComponent("source-\(UUID().uuidString).image")
                do {
                    try FileManager.default.copyItem(at: source, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: Failure.loadFailed)
                }
            }
        }
    }

    private static func loadURL(from provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let url = item as? URL, error == nil {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: Failure.loadFailed)
                }
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: NSString.self) { value, error in
                if let value = value as? String, error == nil {
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(throwing: Failure.loadFailed)
                }
            }
        }
    }
}
#endif
