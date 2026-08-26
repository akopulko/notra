import ImageIO
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct MarkdownImageView: View {
    @Environment(\.markdownStyle) private var style
    @Environment(\.secondaryBackgroundFill) private var secondaryBackgroundFill
    @State private var state: LoadingState = .idle

    let reference: MarkdownImageReference
    let context: MarkdownRenderContext

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                placeholder(systemImage: "photo")
                    .redacted(reason: .placeholder)
            case let .loaded(image):
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 6))
            case .failed:
                placeholder(systemImage: "exclamationmark.triangle")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(reference.alt.isEmpty ? "Image" : reference.alt)
        .task(id: resolvedURL) {
            await loadImage()
        }
    }

    private var resolvedURL: URL? {
        Self.resolvedURL(for: reference.source, context: context)
    }

    static func resolvedURL(for source: String?, context: MarkdownRenderContext) -> URL? {
        MarkdownAttachmentReferences.resolve(source, assetBaseURL: context.assetBaseURL)
    }

    private func placeholder(systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(reference.alt.isEmpty ? "Image" : reference.alt)
                .lineLimit(2)
        }
        .font(.callout)
        .foregroundStyle(style.secondaryTextColor)
        .padding(12)
        .background(secondaryBackgroundFill.view)
        .clipShape(.rect(cornerRadius: 6))
    }

    private func loadImage() async {
        guard let resolvedURL else {
            state = .failed
            return
        }

        state = .loading

        do {
            let thumbnail = if resolvedURL.isFileURL {
                await Task.detached(priority: .utility) {
                    Self.downsampledImage(from: resolvedURL)
                }.value
            } else {
                try await MarkdownImageLoader.shared.thumbnail(for: resolvedURL)
            }

            guard let thumbnail,
                  let image = platformImage(from: thumbnail)
            else {
                state = .failed
                return
            }
            state = .loaded(image)
        } catch {
            state = .failed
        }
    }

    private nonisolated static func downsampledImage(from url: URL) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        return downsampledImage(from: source)
    }

    fileprivate nonisolated static func downsampledImage(from data: Data) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        return downsampledImage(from: source)
    }

    private nonisolated static func downsampledImage(from source: CGImageSource) -> CGImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    private func platformImage(from image: CGImage) -> Image? {
        #if os(iOS)
        return Image(uiImage: UIImage(cgImage: image))
        #elseif os(macOS)
        return Image(nsImage: NSImage(cgImage: image, size: .zero))
        #else
        return nil
        #endif
    }
}

private enum LoadingState {
    case idle
    case loading
    case loaded(Image)
    case failed
}

private actor MarkdownImageLoader {
    static let shared = MarkdownImageLoader()

    private var cache: [URL: Data] = [:]
    private var tasks: [URL: Task<Data, Error>] = [:]

    func thumbnail(for url: URL) async throws -> CGImage? {
        let data = try await data(for: url)
        return await Task.detached(priority: .utility) {
            MarkdownImageView.downsampledImage(from: data)
        }.value
    }

    func data(for url: URL) async throws -> Data {
        if let cached = cache[url] {
            return cached
        }

        if let task = tasks[url] {
            return try await task.value
        }

        let task = Task<Data, Error> {
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        }

        tasks[url] = task

        do {
            let data = try await task.value
            cache[url] = data
            tasks[url] = nil
            return data
        } catch {
            tasks[url] = nil
            throw error
        }
    }
}
