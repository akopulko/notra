import CoreGraphics
import Foundation
import ImageIO

/// Decodes a bounded image thumbnail without retaining the source image in ImageIO's cache.
///
/// Callers choose their own pixel limit so sidebar rows and inspector tiles retain their
/// existing visual quality while sharing the same orientation and memory policy.
enum ImageThumbnailDecoder {
    nonisolated static func decode(from url: URL, maximumPixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }
}
