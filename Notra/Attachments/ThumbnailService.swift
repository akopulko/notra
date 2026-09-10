import CoreGraphics
import Foundation

/// Shares bounded thumbnail decoding between note rows and the attachment inspector.
actor ThumbnailService {
    static let shared = ThumbnailService()

    private let cache: NSCache<NSString, CGImage>
    private var inFlight: [String: Task<CGImage?, Never>] = [:]

    init() {
        cache = NSCache()
        cache.countLimit = 256
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func thumbnail(for url: URL, maximumPixelSize: Int) async -> CGImage? {
        let canonicalURL = url.standardizedFileURL
        let key = cacheKey(for: canonicalURL, maximumPixelSize: maximumPixelSize)

        if let cachedImage = cache.object(forKey: key as NSString) {
            return cachedImage
        }

        if let existingTask = inFlight[key] {
            return await existingTask.value
        }

        let task = Task.detached(priority: .utility) {
            ImageThumbnailDecoder.decode(from: canonicalURL, maximumPixelSize: maximumPixelSize)
        }
        inFlight[key] = task

        let image = await task.value
        inFlight[key] = nil

        if let image {
            cache.setObject(image, forKey: key as NSString, cost: image.width * image.height * 4)
        }
        return image
    }

    private func cacheKey(for url: URL, maximumPixelSize: Int) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modificationTime = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
        let fileSize = values?.fileSize ?? 0
        return "\(url.absoluteString)|\(maximumPixelSize)|\(modificationTime)|\(fileSize)"
    }
}
